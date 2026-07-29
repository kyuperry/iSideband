//go:build android || darwin || ios || linux

package runcore

import "golang.org/x/sys/unix"

func setXattrTag(path, key string, value []byte) error {
	return unix.Setxattr(path, key, value, 0)
}

func hasXattrTag(path, key string) bool {
	buf := make([]byte, 64)
	n, err := unix.Getxattr(path, key, buf)
	return err == nil && n > 0
}

func getXattrTagString(path, key string) (string, bool) {
	// Try a reasonably sized buffer first, then fall back to the reported size.
	buf := make([]byte, 256)
	n, err := unix.Getxattr(path, key, buf)
	if err == nil && n > 0 {
		return string(buf[:n]), true
	}
	// If buffer was too small, query required size and retry.
	if err == unix.ERANGE {
		sz, err2 := unix.Getxattr(path, key, nil)
		if err2 != nil || sz <= 0 {
			return "", false
		}
		buf = make([]byte, sz)
		n, err = unix.Getxattr(path, key, buf)
		if err == nil && n > 0 {
			return string(buf[:n]), true
		}
	}
	return "", false
}

func clearXattrTag(path, key string) error {
	return unix.Removexattr(path, key)
}
