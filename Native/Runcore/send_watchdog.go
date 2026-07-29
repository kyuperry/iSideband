package runcore

import (
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/svanichkin/go-lxmf/lxmf"
	"github.com/svanichkin/go-reticulum/rns"
)

const sendLastAttemptXattr = "user.send_last_attempt"
const sendStateXattr = "user.send_state"
const sendStatePending = "pending"
const sendErrorsDirName = ".errors"
const sendServiceXattr = "user.service"
const sendServiceLXMF = "lxmf"
const sendFromXattr = "user.from"

func (n *Node) startSendWatchdog() {
	if n == nil {
		return
	}
	if n.announceStop == nil {
		n.announceStop = make(chan struct{})
	}
	sendDir := strings.TrimSpace(n.sendDir)
	if sendDir == "" {
		return
	}

	go func() {
		scan := func() { n.scanSendDirOnce() }

		w, err := fsnotify.NewWatcher()
		if err != nil {
			t := time.NewTicker(2 * time.Second)
			defer t.Stop()
			for {
				select {
				case <-t.C:
					scan()
				case <-n.announceStop:
					return
				}
			}
		}
		defer w.Close()

		_ = w.Add(sendDir)

		var debounceMu sync.Mutex
		var debounce *time.Timer
		trigger := func() {
			debounceMu.Lock()
			defer debounceMu.Unlock()
			if debounce != nil {
				debounce.Stop()
			}
			debounce = time.AfterFunc(400*time.Millisecond, scan)
		}

		scan()

		for {
			select {
			case <-n.announceStop:
				return
			case _, ok := <-w.Events:
				if !ok {
					return
				}
				trigger()
			case _, ok := <-w.Errors:
				if !ok {
					return
				}
				// iCloud FS can be flaky; keep a light poll as fallback.
				t := time.NewTicker(3 * time.Second)
				for {
					select {
					case <-t.C:
						scan()
					case <-n.announceStop:
						t.Stop()
						return
					case _, ok := <-w.Errors:
						if !ok {
							t.Stop()
							return
						}
					}
				}
			}
		}
	}()
}

func (n *Node) scanSendDirOnce() {
	if n == nil || n.router == nil {
		return
	}
	sendDir := strings.TrimSpace(n.sendDir)
	if sendDir == "" {
		return
	}

	entries, err := os.ReadDir(sendDir)
	if err != nil {
		return
	}
	for _, e := range entries {
		name := e.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		p := filepath.Join(sendDir, name)
		if e.IsDir() {
			n.processSendContainer(p)
			continue
		}
		n.processSendFile(p)
	}
}

func (n *Node) processSendContainer(dir string) {
	service := n.readSendService(dir)
	if service == "" {
		if !n.inferLegacySendContainer(dir) {
			n.moveSendToErrors(dir)
			return
		}
		service = sendServiceLXMF
	}
	if service != sendServiceLXMF {
		// Unknown service - ignore for now (future: other services).
		return
	}
	dest := n.readSendToValidated(dir)
	if dest == "" {
		n.moveSendToErrors(dir)
		return
	}
	n.ensureSendFrom(dir)

	n.processSendFolderByDest(dir, dest)
}

func (n *Node) processSendFile(path string) {
	service := n.readSendService(path)
	if service == "" {
		n.moveSendToErrors(path)
		return
	}
	if service != sendServiceLXMF {
		return
	}
	dest := n.readSendToValidated(path)
	if dest == "" {
		n.moveSendToErrors(path)
		return
	}
	n.ensureSendFrom(path)
	n.processSendPaths(dest, []string{path})
}

func (n *Node) inferLegacySendContainer(dir string) bool {
	// Backwards-compat: older UI wrote send/<destHashHex>/... without xattrs.
	// If the folder name looks like a destination hash, treat it as LXMF to=<dest>.
	if n == nil {
		return false
	}
	base := strings.ToLower(strings.TrimSpace(filepath.Base(dir)))
	if len(base) != 32 {
		return false
	}
	// Validate hex (32 chars). We do manual rune checks to avoid partial-parse pitfalls.
	for _, r := range base {
		if (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') {
			continue
		}
		return false
	}

	// Mark the container itself (folder-level send workflow).
	_ = setXattrTag(dir, sendServiceXattr, []byte(sendServiceLXMF))
	_ = setXattrTag(dir, messageToXattr, []byte(base))
	n.ensureSendFrom(dir)
	return true
}

func (n *Node) readSendService(path string) string {
	raw, ok := getXattrTagString(path, sendServiceXattr)
	if !ok {
		return ""
	}
	return strings.ToLower(strings.TrimSpace(raw))
}

func (n *Node) readSendToValidated(path string) string {
	raw, ok := getXattrTagString(path, messageToXattr)
	if !ok {
		return ""
	}
	dest := strings.ToLower(strings.TrimSpace(raw))
	if len(dest) != 32 {
		return ""
	}
	return dest
}

func (n *Node) ensureSendFrom(path string) {
	if n == nil {
		return
	}
	path = strings.TrimSpace(path)
	if path == "" {
		return
	}
	if hasXattrTag(path, sendFromXattr) {
		return
	}
	me := strings.ToLower(strings.TrimSpace(n.DestinationHashHex()))
	if me == "" {
		return
	}
	_ = setXattrTag(path, sendFromXattr, []byte(me))
}

func (n *Node) processSendFolderByDest(dir string, destHashHex string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	paths := make([]string, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		p := filepath.Join(dir, name)
		paths = append(paths, p)
	}
	n.processSendPaths(destHashHex, paths)
}

func (n *Node) processSendPaths(destHashHex string, paths []string) {
	destHashHex = strings.ToLower(strings.TrimSpace(destHashHex))
	if destHashHex == "" || len(destHashHex) != 32 {
		return
	}
	if len(paths) == 0 {
		return
	}

	// Normalize file names in-place (timestamp prefix) per parent folder.
	for _, p := range paths {
		n.normalizeSendFilename(p)
	}

	sort.Strings(paths)
	if len(paths) == 0 {
		return
	}

	// Mark all current files as pending; we keep them in send/<dest> and rely on xattr for status.
	for _, p := range paths {
		n.markSendPending(p)
	}

	for _, attachPath := range paths {
		data, err := os.ReadFile(attachPath)
		if err != nil || len(data) == 0 {
			continue
		}
		mime := detectAvatarMime(data)
		name := filepath.Base(attachPath)
		info, err := n.StoreOutgoingAttachment(data, mime, name)
		if err != nil || info.HashHex == "" {
			rns.Logf(rns.LOG_NOTICE, "send folder: store attachment failed dest=%s err=%v", destHashHex, err)
			return
		}
		content := formatAttachmentMessage(info.HashHex, info.Mime, info.Name, info.Size)
		msg, err := n.SendHex(destHashHex, SendOptions{Title: "img", Content: content})
		if err != nil {
			rns.Logf(rns.LOG_NOTICE, "send folder: send attachment failed dest=%s err=%v", destHashHex, err)
			return
		}
		n.moveSentFileToMessages(destHashHex, attachPath, msg, lxmf.MessageSent)
	}
}

func formatAttachmentMessage(hashHex, mime, name string, size int) string {
	var lines []string
	lines = append(lines, "hash="+strings.TrimSpace(hashHex))
	if strings.TrimSpace(mime) != "" {
		lines = append(lines, "mime="+strings.TrimSpace(mime))
	}
	if strings.TrimSpace(name) != "" {
		lines = append(lines, "name="+strings.TrimSpace(name))
	}
	if size > 0 {
		lines = append(lines, "size="+strconv.Itoa(size))
	}
	return strings.Join(lines, "\n")
}

func (n *Node) markSendPending(path string) {
	if n == nil {
		return
	}
	path = strings.TrimSpace(path)
	if path == "" {
		return
	}
	_ = setXattrTag(path, sendStateXattr, []byte(sendStatePending))
	_ = setXattrTag(path, sendLastAttemptXattr, []byte(strconv.FormatInt(time.Now().Unix(), 10)))
}

func hasMessageTimestampPrefix(name string) bool {
	// Expected: "YYYY-MM-DD HH꞉MM" at the beginning (length 17) where ꞉ is U+A789.
	if len(name) < 17 {
		return false
	}
	p := name[:17]
	// yyyy-mm-dd HH꞉MM
	return strings.Contains(p, "꞉") && p[4] == '-' && p[7] == '-' && p[10] == ' '
}

func (n *Node) normalizeSendFilenames(dir string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	prefix := formatMessageMinute(time.Now())
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		oldName := e.Name()
		if strings.HasPrefix(oldName, ".") {
			continue
		}
		if hasMessageTimestampPrefix(oldName) {
			continue
		}
		newName := prefix + " " + oldName
		_ = os.Rename(filepath.Join(dir, oldName), filepath.Join(dir, newName))
	}
}

func (n *Node) normalizeSendFilename(path string) {
	path = strings.TrimSpace(path)
	if path == "" {
		return
	}
	base := filepath.Base(path)
	if strings.HasPrefix(base, ".") {
		return
	}
	if hasMessageTimestampPrefix(base) {
		return
	}
	prefix := formatMessageMinute(time.Now())
	newName := prefix + " " + base
	_ = os.Rename(path, filepath.Join(filepath.Dir(path), newName))
}

func (n *Node) moveSendToErrors(path string) {
	sendDir := strings.TrimSpace(n.sendDir)
	path = strings.TrimSpace(path)
	if sendDir == "" || path == "" {
		return
	}
	errorsDir := filepath.Join(sendDir, sendErrorsDirName)
	_ = os.MkdirAll(errorsDir, 0o755)
	dst := filepath.Join(errorsDir, filepath.Base(path))
	dst = uniquePath(dst)
	if err := os.Rename(path, dst); err != nil {
		// Fallback to copy+remove if rename fails.
		if st, stErr := os.Stat(path); stErr == nil && st.IsDir() {
			// Directory fallback: best-effort leave it in place if rename fails.
			return
		}
		if err2 := copyFile(path, dst); err2 == nil {
			_ = os.Remove(path)
		}
	}
}

func (n *Node) moveSentFileToMessages(destHashHex, srcPath string, msg *lxmf.LXMessage, initialState byte) {
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
	n.ensureMessagesDirToTag(root, destHashHex)

	base := filepath.Base(srcPath)
	dst := filepath.Join(root, base)
	if _, err := os.Stat(dst); err == nil {
		dst = uniquePath(dst)
	}
	if err := os.Rename(srcPath, dst); err != nil {
		// Cross-device/iCloud corner: fallback to copy+remove.
		if err2 := copyFile(srcPath, dst); err2 == nil {
			_ = os.Remove(srcPath)
		}
	}

	_ = clearXattrTag(dst, sendStateXattr)
	_ = clearXattrTag(dst, sendLastAttemptXattr)

	id := msgIDHex(msg)
	if id != "" {
		n.trackOutboundMessageFile(id, dst)
		n.setMessageFileStateByMsgID(id, initialState)
	} else if initialState != 0 {
		_ = setXattrTag(dst, messageStateXattr, []byte(strconv.Itoa(int(initialState))))
	}
}

func (n *Node) ensureMessagesDirToTag(dir string, to string) {
	if n == nil {
		return
	}
	dir = strings.TrimSpace(dir)
	to = strings.ToLower(strings.TrimSpace(to))
	if dir == "" || to == "" {
		return
	}
	if hasXattrTag(dir, messageToXattr) {
		return
	}
	_ = setXattrTag(dir, messageToXattr, []byte(to))
}
