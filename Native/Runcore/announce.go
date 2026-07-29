package runcore

import (
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/svanichkin/go-reticulum/rns"
)

type AnnounceEntry struct {
	DestinationHashHex string `json:"destination_hash_hex"`
	DisplayName        string `json:"display_name,omitempty"`
	AvatarHashHex      string `json:"avatar_hash_hex,omitempty"`
	AvatarMime         string `json:"avatar_mime,omitempty"`
	AvatarSize         int    `json:"avatar_size,omitempty"`
	AvatarUpdated      int64  `json:"avatar_updated,omitempty"`
	LastSeen           int64  `json:"last_seen"`
	AppDataLen         int    `json:"app_data_len,omitempty"`
}

const announceStorageFileName = "announces.json"

type announceLogger struct {
	node         *Node
	aspectFilter string
}

func newAnnounceLogger(node *Node) *announceLogger {
	return &announceLogger{
		node:         node,
		aspectFilter: "",
	}
}

func (h *announceLogger) AspectFilter() string {
	return h.aspectFilter
}

func (h *announceLogger) ReceivedAnnounce(destinationHash []byte, announcedIdentity *rns.Identity, appData []byte) {
	if h == nil || h.node == nil {
		return
	}
	destHex := hex.EncodeToString(destinationHash)
	displayName, av := parseAnnounceAppData(appData)
	if displayName != "" {
		h.node.renameContactFolderFromAnnounce(destHex, displayName)
	}
	knownAvatarHashHex := ""
	h.node.announceMu.Lock()
	if prev, ok := h.node.announces[destHex]; ok {
		knownAvatarHashHex = prev.AvatarHashHex
	}
	h.node.announceMu.Unlock()
	h.node.recordAnnounce(AnnounceEntry{
		DestinationHashHex: destHex,
		DisplayName:        displayName,
		AvatarHashHex:      strings.ToLower(strings.TrimSpace(av.HashHex)),
		AvatarMime:         strings.TrimSpace(av.Mime),
		AvatarSize:         av.Size,
		AvatarUpdated:      av.Updated,
		LastSeen:           time.Now().Unix(),
		AppDataLen:         len(appData),
	})
	if av.HashHex != "" {
		h.node.maybeFetchAndStoreContactAvatar(destHex, appData, knownAvatarHashHex)
	}
	if displayName != "" {
		rns.Logf(rns.LOG_DEBUG, "Announce rx %s name=%q", destHex, displayName)
	} else {
		rns.Logf(rns.LOG_DEBUG, "Announce rx %s", destHex)
	}
}

func (n *Node) initAnnounceHandler() {
	if n == nil || n.announceHandler != nil {
		return
	}
	h := newAnnounceLogger(n)
	rns.RegisterAnnounceHandler(h)
	n.announceHandler = h
}

func (n *Node) recordAnnounce(entry AnnounceEntry) {
	if n == nil {
		return
	}
	n.announceMu.Lock()
	if n.announces == nil {
		n.announces = make(map[string]AnnounceEntry)
	}
	n.announces[entry.DestinationHashHex] = entry
	entries := make([]AnnounceEntry, 0, len(n.announces))
	for _, e := range n.announces {
		entries = append(entries, e)
	}
	n.announceMu.Unlock()

	n.persistAnnouncesToDisk(entries)
}

func (n *Node) announceStoragePath() string {
	if n == nil {
		return ""
	}
	base := n.storageDir
	if base == "" {
		base = filepath.Join(n.opts.Dir, "storage")
	}
	if base == "" {
		return ""
	}
	return filepath.Join(base, announceStorageFileName)
}

func (n *Node) ensureAnnounceStorageDir() {
	path := n.announceStoragePath()
	if path == "" {
		return
	}
	dir := filepath.Dir(path)
	if dir == "" {
		return
	}
	_ = os.MkdirAll(dir, 0o755)
}

func (n *Node) loadAnnouncesFromDisk() {
	path := n.announceStoragePath()
	if path == "" {
		return
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return
	}
	var entries []AnnounceEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		var wrapped struct {
			Announces []AnnounceEntry `json:"announces"`
		}
		if err := json.Unmarshal(data, &wrapped); err != nil {
			return
		}
		entries = wrapped.Announces
	}
	n.announceMu.Lock()
	if n.announces == nil {
		n.announces = make(map[string]AnnounceEntry)
	}
	for _, entry := range entries {
		if entry.DestinationHashHex == "" {
			continue
		}
		n.announces[entry.DestinationHashHex] = entry
	}
	n.announceMu.Unlock()
}

func (n *Node) persistAnnouncesToDisk(entries []AnnounceEntry) {
	path := n.announceStoragePath()
	if path == "" {
		return
	}
	dir := filepath.Dir(path)
	if dir != "" {
		_ = os.MkdirAll(dir, 0o755)
	}
	data, err := json.Marshal(map[string]any{"announces": entries})
	if err != nil {
		return
	}
	_ = os.WriteFile(path, data, 0o644)
}

func (n *Node) announceSnapshot() []AnnounceEntry {
	if n == nil {
		return nil
	}
	n.announceMu.Lock()
	entries := make([]AnnounceEntry, 0, len(n.announces))
	for _, entry := range n.announces {
		entries = append(entries, entry)
	}
	n.announceMu.Unlock()
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].LastSeen > entries[j].LastSeen
	})
	return entries
}

func (n *Node) AnnouncesJSON() string {
	if n == nil {
		return `{"announces":[],"error":"node not started"}`
	}
	resp := map[string]any{
		"announces": n.announceSnapshot(),
	}
	b, err := json.Marshal(resp)
	if err != nil {
		return `{"announces":[],"error":"marshal failed"}`
	}
	return string(b)
}

// (parsing moved to parseAnnounceAppData in contact_avatar_store.go)
