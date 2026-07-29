package runcore

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/svanichkin/go-reticulum/rns"
)

var inboundAttachmentMu sync.Mutex
var inboundAttachmentInFlight = map[string]struct{}{}

func (n *Node) persistInboundAttachmentAsync(srcHashHex, prefix, name, ext, attachmentHashHex string, tsUnix int64, to string) {
	if n == nil {
		return
	}
	srcHashHex = strings.ToLower(strings.TrimSpace(srcHashHex))
	attachmentHashHex = strings.ToLower(strings.TrimSpace(attachmentHashHex))
	if srcHashHex == "" || attachmentHashHex == "" {
		return
	}
	key := srcHashHex + ":" + attachmentHashHex

	inboundAttachmentMu.Lock()
	if _, ok := inboundAttachmentInFlight[key]; ok {
		inboundAttachmentMu.Unlock()
		return
	}
	inboundAttachmentInFlight[key] = struct{}{}
	inboundAttachmentMu.Unlock()

	go func() {
		defer func() {
			inboundAttachmentMu.Lock()
			delete(inboundAttachmentInFlight, key)
			inboundAttachmentMu.Unlock()
		}()

		timeout := 30 * time.Second
		fetch, err := n.ContactAttachmentPathHex(srcHashHex, attachmentHashHex, timeout)
		if err != nil {
			rns.Logf(rns.LOG_NOTICE, "attachment fetch: failed src=%s hash=%s err=%v", srcHashHex, attachmentHashHex, err)
			return
		}
		if fetch.NotPresent || strings.TrimSpace(fetch.Path) == "" {
			return
		}

		root := strings.TrimSpace(n.messagesDir)
		if root == "" {
			return
		}
		dstDir := filepath.Join(root, srcHashHex)
		_ = os.MkdirAll(dstDir, 0o755)
		n.ensureMessagesDirFromTag(dstDir, srcHashHex)

		base := sanitizeMessageName(strings.TrimSpace(name))
		if base == "" {
			base = attachmentHashHex
		}
		if ext != "" && !strings.HasSuffix(strings.ToLower(base), ext) {
			base += ext
		}
		dstPath := uniquePath(filepath.Join(dstDir, prefix+" "+base))

		if err := copyFile(fetch.Path, dstPath); err != nil {
			rns.Logf(rns.LOG_WARNING, "attachment fetch: persist failed src=%s err=%v", srcHashHex, err)
			return
		}
		n.setInboundMessageFileTags(dstPath, tsUnix, srcHashHex, to)
	}()
}

func copyFile(srcPath, dstPath string) error {
	src, err := os.Open(srcPath)
	if err != nil {
		return err
	}
	defer src.Close()
	dst, err := os.Create(dstPath)
	if err != nil {
		return err
	}
	defer func() { _ = dst.Close() }()
	if _, err := io.Copy(dst, src); err != nil {
		return err
	}
	return dst.Sync()
}
