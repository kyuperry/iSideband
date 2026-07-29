package runcore

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/svanichkin/go-reticulum/rns"
	umsgpack "github.com/svanichkin/go-reticulum/rns/vendor"
)

type announceAvatarMeta struct {
	HashHex  string
	Mime     string
	Size     int
	Updated  int64
	Present  bool
	ParsedOK bool
}

func parseAnnounceAppData(appData []byte) (displayName string, avatar announceAvatarMeta) {
	if len(appData) == 0 {
		return "", announceAvatarMeta{}
	}
	var unpacked []any
	if err := umsgpack.Unpackb(appData, &unpacked); err != nil {
		return "", announceAvatarMeta{}
	}
	if len(unpacked) > 0 {
		switch v := unpacked[0].(type) {
		case []byte:
			if len(v) > 0 {
				displayName = string(v)
			}
		case string:
			displayName = v
		}
	}
	if len(unpacked) > 2 {
		if m, ok := unpacked[2].(map[any]any); ok {
			avatar.ParsedOK = true
			if hv, ok := m["h"]; ok {
				if b, ok := hv.([]byte); ok && len(b) > 0 {
					avatar.HashHex = hex.EncodeToString(b)
				}
			}
			if tv, ok := m["t"]; ok {
				if s, ok := tv.(string); ok {
					avatar.Mime = s
				}
			}
			if sv, ok := m["s"]; ok {
				switch n := sv.(type) {
				case int:
					avatar.Size = n
				case int64:
					avatar.Size = int(n)
				case float64:
					avatar.Size = int(n)
				}
			}
			if uv, ok := m["u"]; ok {
				switch n := uv.(type) {
				case int64:
					avatar.Updated = n
				case int:
					avatar.Updated = int64(n)
				case float64:
					avatar.Updated = int64(n)
				}
			}
			avatar.Present = avatar.HashHex != "" || avatar.Mime != "" || avatar.Size != 0 || avatar.Updated != 0
		}
	}
	return displayName, avatar
}

func contactDirByDestinationHashHex(contactsDir, destHashHex string) (string, error) {
	contactsDir = strings.TrimSpace(contactsDir)
	destHashHex = strings.ToLower(strings.TrimSpace(destHashHex))
	if contactsDir == "" || destHashHex == "" {
		return "", errors.New("missing params")
	}
	entries, err := os.ReadDir(contactsDir)
	if err != nil {
		return "", err
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(contactsDir, e.Name())
		b, err := os.ReadFile(filepath.Join(dir, meLXMFFileName))
		if err != nil {
			continue
		}
		if strings.EqualFold(strings.TrimSpace(string(b)), destHashHex) {
			return dir, nil
		}
	}
	return "", os.ErrNotExist
}

var avatarFetchMu sync.Mutex
var avatarFetchInFlight = map[string]struct{}{}

func (n *Node) maybeFetchAndStoreContactAvatar(destHashHex string, appData []byte, knownAvatarHashHex string) {
	if n == nil {
		return
	}
	destHashHex = strings.ToLower(strings.TrimSpace(destHashHex))
	if destHashHex == "" {
		return
	}
	contactsDir := strings.TrimSpace(n.contactsDir)
	if contactsDir == "" {
		return
	}
	// Only for contacts created by the app (folder exists and contains lxmf).
	contactDir, err := contactDirByDestinationHashHex(contactsDir, destHashHex)
	if err != nil || contactDir == "" {
		return
	}
	_, avatar := parseAnnounceAppData(appData)
	if !avatar.Present || avatar.HashHex == "" {
		return
	}
	if knownAvatarHashHex != "" && strings.EqualFold(knownAvatarHashHex, avatar.HashHex) {
		return
	}

	avatarFetchMu.Lock()
	if _, ok := avatarFetchInFlight[destHashHex]; ok {
		avatarFetchMu.Unlock()
		return
	}
	avatarFetchInFlight[destHashHex] = struct{}{}
	avatarFetchMu.Unlock()

	go func() {
		defer func() {
			avatarFetchMu.Lock()
			delete(avatarFetchInFlight, destHashHex)
			avatarFetchMu.Unlock()
		}()

		timeout := 20 * time.Second
		data, mime, hashHex, err := n.fetchContactAvatarBytesHex(destHashHex, timeout)
		if err != nil {
			rns.Logf(rns.LOG_NOTICE, "avatar fetch: failed dest=%s err=%v", destHashHex, err)
			return
		}
		if len(data) == 0 {
			return
		}
		if hashHex == "" {
			sum := sha256.Sum256(data)
			hashHex = hex.EncodeToString(sum[:])
		}

		// Re-check contact dir (may have been removed/renamed).
		contactDir, err := contactDirByDestinationHashHex(contactsDir, destHashHex)
		if err != nil || contactDir == "" {
			return
		}

		ext := avatarExtFromMimeOrData(mime, data)
		target := filepath.Join(contactDir, "avatar"+ext)
		if err := os.WriteFile(target, data, 0o644); err != nil {
			rns.Logf(rns.LOG_WARNING, "avatar fetch: write failed dest=%s err=%v", destHashHex, err)
			return
		}
		_ = removeOtherAvatarFiles(contactDir, filepath.Base(target))
	}()
}

func removeOtherAvatarFiles(dir string, keepBase string) error {
	candidates := []string{"avatar.png", "avatar.jpg", "avatar.jpeg", "avatar.heic", "avatar.bin"}
	for _, base := range candidates {
		if base == keepBase {
			continue
		}
		_ = os.Remove(filepath.Join(dir, base))
	}
	return nil
}

func avatarExtFromMimeOrData(mime string, data []byte) string {
	mime = strings.ToLower(strings.TrimSpace(mime))
	switch mime {
	case "image/png":
		return ".png"
	case "image/jpeg", "image/jpg":
		return ".jpg"
	case "image/heic", "image/heif":
		return ".heic"
	}
	if bytes.HasPrefix(data, []byte{0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a}) {
		return ".png"
	}
	if bytes.HasPrefix(data, []byte{0xff, 0xd8, 0xff}) {
		return ".jpg"
	}
	if len(data) >= 12 && string(data[4:8]) == "ftyp" {
		return ".heic"
	}
	return ".bin"
}
