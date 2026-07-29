package runcore

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/svanichkin/go-reticulum/rns"
)

func (n *Node) renameContactFolderFromAnnounce(destHashHex, displayName string) {
	if n == nil {
		return
	}
	destHashHex = strings.ToLower(strings.TrimSpace(destHashHex))
	displayName = strings.TrimSpace(displayName)
	if destHashHex == "" || displayName == "" {
		return
	}
	if strings.TrimSpace(n.contactsDir) == "" {
		return
	}

	desired := sanitizeContactFolderName(displayName)
	if desired == "" {
		return
	}

	entries, err := os.ReadDir(n.contactsDir)
	if err != nil {
		return
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := filepath.Join(n.contactsDir, e.Name())

		// Never rename our own "me" folder.
		if hasXattrTag(dir, meTagXattr) {
			continue
		}

		b, err := os.ReadFile(filepath.Join(dir, meLXMFFileName))
		if err != nil {
			continue
		}
		if !strings.EqualFold(strings.TrimSpace(string(b)), destHashHex) {
			continue
		}

		currentName := filepath.Base(dir)
		if currentName == desired {
			return
		}

		target := filepath.Join(n.contactsDir, desired)
		if err := os.Rename(dir, target); err == nil {
			return
		}

		// Resolve name collisions by suffixing.
		for i := 2; i < 10_000; i++ {
			candidate := filepath.Join(n.contactsDir, desired+"-"+strconv.Itoa(i))
			if _, err := os.Stat(candidate); err == nil {
				continue
			}
			if err := os.Rename(dir, candidate); err == nil {
				return
			}
		}
		rns.Logf(rns.LOG_WARNING, "runcore: rename contact folder failed dest=%s desired=%q", destHashHex, desired)
		return
	}
}
