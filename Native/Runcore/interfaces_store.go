package runcore

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/svanichkin/configobj"
)

type interfaceDiskEntry struct {
	DirName    string `json:"dir_name"`
	Name       string `json:"name"`
	ShortName  string `json:"short_name,omitempty"`
	Type       string `json:"type,omitempty"`
	Enabled    *bool  `json:"enabled,omitempty"`
	State      string `json:"state"`
	RXB        int64  `json:"rxb,omitempty"`
	TXB        int64  `json:"txb,omitempty"`
	RXS        int64  `json:"rxs,omitempty"`
	TXS        int64  `json:"txs,omitempty"`
	Bitrate    int64  `json:"bitrate,omitempty"`
	UpdatedAt  int64  `json:"updated_at"`
	ConfigName string `json:"config_name,omitempty"`
}

type interfacesDiskSnapshot struct {
	Interfaces []interfaceDiskEntry `json:"interfaces"`
}

func (n *Node) interfacesDir() string {
	if n == nil {
		return ""
	}
	return filepath.Join(n.opts.Dir, "interfaces")
}

func sanitizeInterfaceDirName(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return "unknown"
	}
	// Keep it human-readable, but ensure it's a single path element.
	s = strings.ReplaceAll(s, string(os.PathSeparator), "_")
	if os.PathSeparator != '/' {
		s = strings.ReplaceAll(s, "/", "_")
	}
	s = strings.Trim(s, ". ")
	if s == "" {
		return "unknown"
	}
	return s
}

func anyToString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case []byte:
		return string(t)
	default:
		return ""
	}
}

func anyToInt64(v any) int64 {
	switch t := v.(type) {
	case int:
		return int64(t)
	case int64:
		return t
	case uint64:
		if t > uint64(^uint64(0)>>1) {
			return int64(^uint64(0) >> 1)
		}
		return int64(t)
	case float64:
		return int64(t)
	case json.Number:
		if i, err := t.Int64(); err == nil {
			return i
		}
		if f, err := t.Float64(); err == nil {
			return int64(f)
		}
		return 0
	case string:
		if i, err := strconv.ParseInt(strings.TrimSpace(t), 10, 64); err == nil {
			return i
		}
		return 0
	default:
		return 0
	}
}

func anyToBool(v any) (bool, bool) {
	switch t := v.(type) {
	case bool:
		return t, true
	case string:
		s := strings.ToLower(strings.TrimSpace(t))
		switch s {
		case "1", "y", "yes", "true", "on", "online", "up":
			return true, true
		case "0", "n", "no", "false", "off", "offline", "down":
			return false, true
		default:
			return false, false
		}
	default:
		return false, false
	}
}

func (n *Node) configuredInterfaces() ([]configuredInterfaceEntry, error) {
	if n == nil || n.reticulum == nil || n.reticulum.ConfigPath == "" {
		return nil, fmt.Errorf("reticulum not started")
	}
	cfg, err := configobj.Load(n.reticulum.ConfigPath)
	if err != nil {
		return nil, err
	}
	if !cfg.HasSection("interfaces") {
		return nil, nil
	}
	sec := cfg.Section("interfaces")
	names := sec.Sections()
	sort.Strings(names)
	out := make([]configuredInterfaceEntry, 0, len(names))
	for _, name := range names {
		s := sec.Subsection(name)
		typ, _ := s.Get("type")
		enabled := false
		if v, ok := s.Get("interface_enabled"); ok {
			enabled = parseTruthyString(v)
		} else if v, ok := s.Get("enabled"); ok {
			enabled = parseTruthyString(v)
		} else if v, ok := s.Get("enable"); ok {
			enabled = parseTruthyString(v)
		}
		out = append(out, configuredInterfaceEntry{Name: name, Type: typ, Enabled: enabled})
	}
	return out, nil
}

func (n *Node) runtimeInterfaceEntries() ([]map[string]any, error) {
	if n == nil || n.reticulum == nil {
		return nil, fmt.Errorf("reticulum not started")
	}
	stats := n.reticulum.GetInterfaceStats()
	raw, ok := stats["interfaces"]
	if !ok {
		return nil, nil
	}
	switch list := raw.(type) {
	case []any:
		out := make([]map[string]any, 0, len(list))
		for _, v := range list {
			if m, ok := v.(map[string]any); ok {
				out = append(out, m)
			}
		}
		return out, nil
	case []map[string]any:
		out := make([]map[string]any, 0, len(list))
		for i := range list {
			out = append(out, list[i])
		}
		return out, nil
	default:
		return nil, nil
	}
}

func (n *Node) persistInterfacesSnapshotToDisk() error {
	if n == nil {
		return nil
	}
	base := n.interfacesDir()
	if base == "" {
		return nil
	}

	configured, _ := n.configuredInterfaces()
	runtime, _ := n.runtimeInterfaceEntries()

	runtimeByShort := make(map[string]map[string]any, len(runtime))
	runtimeByName := make(map[string]map[string]any, len(runtime))
	for _, m := range runtime {
		if sn := strings.TrimSpace(anyToString(m["short_name"])); sn != "" {
			runtimeByShort[sn] = m
		}
		if nm := strings.TrimSpace(anyToString(m["name"])); nm != "" {
			runtimeByName[nm] = m
		}
	}

	seen := make(map[string]bool)
	entries := make([]interfaceDiskEntry, 0, len(configured)+len(runtime))

	for _, cfg := range configured {
		cfgName := strings.TrimSpace(cfg.Name)
		if cfgName == "" {
			continue
		}
		dirName := sanitizeInterfaceDirName(cfgName)
		seen[dirName] = true

		entry := interfaceDiskEntry{
			DirName:    dirName,
			Name:       cfgName,
			Type:       strings.TrimSpace(cfg.Type),
			Enabled:    ptrBool(cfg.Enabled),
			State:      "unknown",
			UpdatedAt:  0,
			ConfigName: cfgName,
		}

		if m, ok := runtimeByShort[cfgName]; ok {
			applyRuntimeStats(&entry, m)
		} else if m, ok := runtimeByName[cfgName]; ok {
			applyRuntimeStats(&entry, m)
		}
		entries = append(entries, entry)
	}

	for _, m := range runtime {
		name := strings.TrimSpace(anyToString(m["short_name"]))
		if name == "" {
			name = strings.TrimSpace(anyToString(m["name"]))
		}
		if name == "" {
			continue
		}
		dirName := sanitizeInterfaceDirName(name)
		if seen[dirName] {
			continue
		}
		entry := interfaceDiskEntry{
			DirName:   dirName,
			Name:      name,
			ShortName: strings.TrimSpace(anyToString(m["short_name"])),
			Type:      strings.TrimSpace(anyToString(m["type"])),
			State:     "unknown",
			UpdatedAt: 0,
		}
		applyRuntimeStats(&entry, m)
		entries = append(entries, entry)
	}

	// Ensure stable, unique directory names.
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Name != entries[j].Name {
			return entries[i].Name < entries[j].Name
		}
		return entries[i].Type < entries[j].Type
	})
	used := make(map[string]bool)
	for i := range entries {
		baseName := sanitizeInterfaceDirName(entries[i].DirName)
		if !used[baseName] {
			entries[i].DirName = baseName
			used[baseName] = true
			continue
		}
		sum := sha256.Sum256([]byte(entries[i].Name))
		entries[i].DirName = fmt.Sprintf("%s-%x", baseName, sum[:3])
		used[entries[i].DirName] = true
	}

	sort.Slice(entries, func(i, j int) bool { return entries[i].DirName < entries[j].DirName })
	snap := interfacesDiskSnapshot{Interfaces: entries}
	b, err := json.Marshal(snap)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(b)

	n.ifaceStateMu.Lock()
	same := n.lastIfacePersistHash == sum
	if !same {
		n.lastIfacePersistHash = sum
	}
	n.ifaceStateMu.Unlock()
	if same {
		return nil
	}

	nowUnix := time.Now().Unix()
	for i := range entries {
		entries[i].UpdatedAt = nowUnix
	}

	if err := os.MkdirAll(base, 0o755); err != nil {
		return err
	}

	// Write an index of active interface dirs.
	var list strings.Builder
	for _, e := range entries {
		list.WriteString(e.DirName)
		list.WriteByte('\n')
	}
	if err := writeFileAtomicString(filepath.Join(base, "list"), list.String(), 0o644); err != nil {
		return err
	}

	for _, e := range entries {
		dir := filepath.Join(base, e.DirName)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
		if err := writeFileAtomicString(filepath.Join(dir, "name"), e.Name+"\n", 0o644); err != nil {
			return err
		}
		if err := writeFileAtomicString(filepath.Join(dir, "short_name"), e.ShortName+"\n", 0o644); err != nil {
			return err
		}
		if err := writeFileAtomicString(filepath.Join(dir, "type"), e.Type+"\n", 0o644); err != nil {
			return err
		}
		if e.Enabled != nil {
			val := "0\n"
			if *e.Enabled {
				val = "1\n"
			}
			if err := writeFileAtomicString(filepath.Join(dir, "enabled"), val, 0o644); err != nil {
				return err
			}
		}
		if err := writeFileAtomicString(filepath.Join(dir, "state"), e.State+"\n", 0o644); err != nil {
			return err
		}
		if err := writeFileAtomicString(filepath.Join(dir, "rxb"), strconv.FormatInt(e.RXB, 10)+"\n", 0o644); err != nil {
			return err
		}
		if err := writeFileAtomicString(filepath.Join(dir, "txb"), strconv.FormatInt(e.TXB, 10)+"\n", 0o644); err != nil {
			return err
		}
		if err := writeFileAtomicString(filepath.Join(dir, "rxs"), strconv.FormatInt(e.RXS, 10)+"\n", 0o644); err != nil {
			return err
		}
		if err := writeFileAtomicString(filepath.Join(dir, "txs"), strconv.FormatInt(e.TXS, 10)+"\n", 0o644); err != nil {
			return err
		}
		if err := writeFileAtomicString(filepath.Join(dir, "bitrate"), strconv.FormatInt(e.Bitrate, 10)+"\n", 0o644); err != nil {
			return err
		}
		if err := writeFileAtomicString(filepath.Join(dir, "updated_at"), strconv.FormatInt(e.UpdatedAt, 10)+"\n", 0o644); err != nil {
			return err
		}
	}

	return nil
}

func ptrBool(v bool) *bool { return &v }

func applyRuntimeStats(dst *interfaceDiskEntry, m map[string]any) {
	if dst == nil || m == nil {
		return
	}
	if s := strings.TrimSpace(anyToString(m["short_name"])); s != "" {
		dst.ShortName = s
	}
	if t := strings.TrimSpace(anyToString(m["type"])); t != "" {
		dst.Type = t
	}

	state := "unknown"
	if b, ok := anyToBool(m["status"]); ok {
		if b {
			state = "online"
		} else {
			state = "offline"
		}
	} else if b, ok := anyToBool(m["online"]); ok {
		if b {
			state = "online"
		} else {
			state = "offline"
		}
	}
	dst.State = state

	dst.RXB = anyToInt64(m["rxb"])
	dst.TXB = anyToInt64(m["txb"])
	dst.RXS = anyToInt64(m["rxs"])
	dst.TXS = anyToInt64(m["txs"])
	dst.Bitrate = anyToInt64(m["bitrate"])
}
