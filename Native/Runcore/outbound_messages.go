package runcore

import (
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/svanichkin/go-lxmf/lxmf"
	"github.com/svanichkin/go-reticulum/rns"
)

func msgIDHex(m *lxmf.LXMessage) string {
	if m == nil {
		return ""
	}
	if len(m.MessageID) > 0 {
		return hex.EncodeToString(m.MessageID)
	}
	if len(m.Hash) > 0 {
		return hex.EncodeToString(m.Hash)
	}
	return ""
}

func (n *Node) persistOutboundText(destHashHex, content string, t time.Time, msg *lxmf.LXMessage) {
	if n == nil {
		return
	}
	destHashHex = strings.ToLower(strings.TrimSpace(destHashHex))
	if destHashHex == "" {
		return
	}
	root := outboundMessageDir(n.messagesDir, destHashHex)
	if root == "" {
		return
	}
	_ = os.MkdirAll(root, 0o755)

	prefix := formatMessageMinute(t)
	path := uniquePath(filepath.Join(root, prefix+".txt"))
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		rns.Logf(rns.LOG_WARNING, "runcore: persist outbound message: %v", err)
		return
	}

	id := msgIDHex(msg)
	if id != "" {
		n.trackOutboundMessageFile(id, path)
		n.setMessageFileStateByMsgID(id, msg.State)
	}
}

func (n *Node) persistOutboundAttachmentCopy(destHashHex, srcPath string, t time.Time, msg *lxmf.LXMessage) {
	if n == nil {
		return
	}
	destHashHex = strings.ToLower(strings.TrimSpace(destHashHex))
	srcPath = strings.TrimSpace(srcPath)
	if destHashHex == "" || srcPath == "" {
		return
	}
	root := outboundMessageDir(n.messagesDir, destHashHex)
	if root == "" {
		return
	}
	_ = os.MkdirAll(root, 0o755)

	prefix := formatMessageMinute(t)
	base := sanitizeMessageName(filepath.Base(srcPath))
	if base == "" {
		base = "file.bin"
	}
	dst := uniquePath(filepath.Join(root, prefix+" "+base))
	if err := copyFile(srcPath, dst); err != nil {
		rns.Logf(rns.LOG_WARNING, "runcore: persist outbound attachment: %v", err)
		return
	}

	id := msgIDHex(msg)
	if id != "" {
		n.trackOutboundMessageFile(id, dst)
		n.setMessageFileStateByMsgID(id, msg.State)
	}
}

// PersistOutboundTextToMessagesDir writes an outbound message file into messagesDir/<destHashHex>/.
// This is used by FFI callers that send messages directly (without the send-folder workflow).
func (n *Node) PersistOutboundTextToMessagesDir(destHashHex, content string, msg *lxmf.LXMessage) {
	n.persistOutboundText(destHashHex, content, time.Now(), msg)
}
