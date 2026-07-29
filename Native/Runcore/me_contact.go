package runcore

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

const meLXMFFileName = "lxmf"

const meTagXattr = "user.me"

func (n *Node) ensureMeContactState(desiredName string) (string, string, error) {
	dir, finalName, err := n.ensureMeContactDir(desiredName)
	if err != nil {
		return "", "", err
	}
	value, err := n.readMeLXMFFile(dir)
	if err == nil && value != "" {
		return dir, finalName, nil
	}
	if err := n.ResetProfile(); err != nil {
		return dir, finalName, err
	}
	dir, finalName, err = n.ensureMeContactDir(finalName)
	if err != nil {
		return "", "", err
	}
	if err := n.writeMeLXMFFile(dir, n.DestinationHashHex()); err != nil {
		return dir, finalName, err
	}
	return dir, finalName, nil
}

func (n *Node) ensureMeContactDir(desiredName string) (string, string, error) {
	if n == nil {
		return "", "", errors.New("node not started")
	}
	if strings.TrimSpace(n.contactsDir) == "" {
		return "", "", errors.New("contacts dir is empty")
	}

	currentDir, err := n.findMeContactDir()
	if err == nil && currentDir != "" {
		currentName := filepath.Base(currentDir)
		finalName := sanitizeContactFolderName(currentName)
		if strings.TrimSpace(desiredName) != "" {
			finalDesired := sanitizeContactFolderName(desiredName)
			if finalDesired != finalName {
				target := filepath.Join(n.contactsDir, finalDesired)
				_ = os.MkdirAll(filepath.Dir(target), 0o755)
				if err := os.Rename(currentDir, target); err == nil {
					currentDir = target
					finalName = finalDesired
				}
			}
		}
		n.clearOtherMeTags(currentDir)
		_ = setXattrTag(currentDir, meTagXattr, []byte("1"))
		n.meDirMu.Lock()
		n.meDir = currentDir
		n.meDirMu.Unlock()
		return currentDir, finalName, nil
	}

	desired := strings.TrimSpace(desiredName)
	if desired == "" {
		desired = "Me"
	}
	finalName := sanitizeContactFolderName(desired)
	target := filepath.Join(n.contactsDir, finalName)
	if err := os.MkdirAll(target, 0o755); err != nil {
		return "", "", err
	}
	n.clearOtherMeTags(target)
	_ = setXattrTag(target, meTagXattr, []byte("1"))
	n.meDirMu.Lock()
	n.meDir = target
	n.meDirMu.Unlock()
	return target, finalName, nil
}

func (n *Node) findMeContactDir() (string, error) {
	if n == nil {
		return "", errors.New("node not started")
	}
	n.meDirMu.RLock()
	cached := n.meDir
	n.meDirMu.RUnlock()
	if cached != "" && hasXattrTag(cached, meTagXattr) {
		return cached, nil
	}
	if strings.TrimSpace(n.contactsDir) == "" {
		return "", errors.New("contacts dir is empty")
	}

	entries, err := os.ReadDir(n.contactsDir)
	if err != nil {
		return "", err
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		p := filepath.Join(n.contactsDir, e.Name())
		if hasXattrTag(p, meTagXattr) {
			n.meDirMu.Lock()
			n.meDir = p
			n.meDirMu.Unlock()
			return p, nil
		}
	}
	return "", os.ErrNotExist
}

func (n *Node) clearOtherMeTags(skip string) {
	entries, _ := os.ReadDir(n.contactsDir)
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		p := filepath.Join(n.contactsDir, e.Name())
		if p == skip {
			continue
		}
		if hasXattrTag(p, meTagXattr) {
			_ = clearXattrTag(p, meTagXattr)
		}
	}
}

func sanitizeContactFolderName(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return "Me"
	}
	name = strings.ReplaceAll(name, string(os.PathSeparator), "_")
	name = strings.ReplaceAll(name, ":", "_")
	name = strings.ReplaceAll(name, "\u0000", "_")
	name = strings.TrimSpace(name)
	if name == "" {
		return "Me"
	}
	if len(name) > 80 {
		return name[:80]
	}
	return name
}

func (n *Node) ensureMeLXMFFile() error {
	if n == nil {
		return errors.New("node not started")
	}
	dir, err := n.findMeContactDir()
	if err != nil || dir == "" {
		var ensureErr error
		dir, _, ensureErr = n.ensureMeContactDir(n.displayName)
		if ensureErr != nil || dir == "" {
			if ensureErr != nil {
				return ensureErr
			}
			return err
		}
	}
	target := filepath.Join(dir, meLXMFFileName)
	if b, err := os.ReadFile(target); err == nil {
		if strings.TrimSpace(string(b)) != "" {
			return nil
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	hash := strings.TrimSpace(n.DestinationHashHex())
	if hash == "" {
		return errors.New("missing destination hash")
	}
	return n.writeMeLXMFFile(dir, hash)
}

func (n *Node) readMeLXMFFile(dir string) (string, error) {
	if strings.TrimSpace(dir) == "" {
		return "", os.ErrNotExist
	}
	b, err := os.ReadFile(filepath.Join(dir, meLXMFFileName))
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

func (n *Node) writeMeLXMFFile(dir, hash string) error {
	dir = strings.TrimSpace(dir)
	hash = strings.TrimSpace(hash)
	if dir == "" {
		return errors.New("me contact dir is empty")
	}
	if hash == "" {
		return errors.New("missing destination hash")
	}
	return os.WriteFile(filepath.Join(dir, meLXMFFileName), []byte(hash), 0o644)
}
