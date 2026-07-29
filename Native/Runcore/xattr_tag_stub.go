//go:build !(android || darwin || ios || linux)

package runcore

func setXattrTag(path, key string, value []byte) error { return nil }
func hasXattrTag(path, key string) bool                { return false }
func getXattrTagString(path, key string) (string, bool) { return "", false }
func clearXattrTag(path, key string) error             { return nil }
