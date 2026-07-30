package runcore

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/svanichkin/configobj"
)

func TestSafeTCPClientDefaultsDisableLegacyPublicTarget(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config")
	config := `[interfaces]
  [[TCP Client Interface]]
    type = TCPClientInterface
    interface_enabled = Yes
    target_host = reticulum.betweentheborders.com
    target_port = 4242
`
	if err := os.WriteFile(path, []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := ensureSafeTCPClientDefaults(path); err != nil {
		t.Fatal(err)
	}
	cfg, err := configobj.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	ifc := cfg.Section("interfaces").Subsection("TCP Client Interface")
	enabled, _ := ifc.Get("interface_enabled")
	if !strings.EqualFold(strings.TrimSpace(enabled), "No") {
		t.Fatalf("legacy public TCP interface remained enabled: %q", enabled)
	}
}

func TestSafeTCPClientDefaultsPreserveConfiguredPi(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config")
	config := `[interfaces]
  [[TCP Client Interface]]
    type = TCPClientInterface
    interface_enabled = Yes
    target_host = 192.168.1.42
    target_port = 4242
`
	if err := os.WriteFile(path, []byte(config), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := ensureSafeTCPClientDefaults(path); err != nil {
		t.Fatal(err)
	}
	cfg, err := configobj.Load(path)
	if err != nil {
		t.Fatal(err)
	}
	ifc := cfg.Section("interfaces").Subsection("TCP Client Interface")
	enabled, _ := ifc.Get("interface_enabled")
	host, _ := ifc.Get("target_host")
	if !strings.EqualFold(strings.TrimSpace(enabled), "Yes") ||
		strings.TrimSpace(host) != "192.168.1.42" {
		t.Fatalf("configured Pi was changed: enabled=%q host=%q", enabled, host)
	}
}
