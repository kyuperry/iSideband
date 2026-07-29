package runcore

import (
	"path/filepath"
	"strconv"
	"strings"
)

const messageStateXattr = "user.msg_state"

func (n *Node) setMessageFileStateByMsgID(msgIDHex string, state byte) {
	if n == nil {
		return
	}
	msgIDHex = strings.ToLower(strings.TrimSpace(msgIDHex))
	if msgIDHex == "" {
		return
	}
	n.outboundMu.Lock()
	path := n.outboundMsgFiles[msgIDHex]
	n.outboundMu.Unlock()
	if path == "" {
		return
	}
	_ = setXattrTag(path, messageStateXattr, []byte(strconv.Itoa(int(state))))
}

func (n *Node) trackOutboundMessageFile(msgIDHex, path string) {
	if n == nil {
		return
	}
	msgIDHex = strings.ToLower(strings.TrimSpace(msgIDHex))
	path = strings.TrimSpace(path)
	if msgIDHex == "" || path == "" {
		return
	}
	n.outboundMu.Lock()
	if n.outboundMsgFiles == nil {
		n.outboundMsgFiles = make(map[string]string)
	}
	n.outboundMsgFiles[msgIDHex] = path
	n.outboundMu.Unlock()
}

func outboundMessageDir(messagesDir, destHashHex string) string {
	messagesDir = strings.TrimSpace(messagesDir)
	destHashHex = strings.ToLower(strings.TrimSpace(destHashHex))
	if messagesDir == "" || destHashHex == "" {
		return ""
	}
	return filepath.Join(messagesDir, destHashHex)
}
