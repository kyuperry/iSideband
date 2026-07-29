package runcore

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/svanichkin/configobj"
	"github.com/svanichkin/go-lxmf/lxmf"
	"github.com/svanichkin/go-reticulum/rns"
	umsgpack "github.com/svanichkin/go-reticulum/rns/vendor"
)

type LogDest = any

type Options struct {
	// RNSConfigDir is an optional Reticulum config dir to use as-is.
	// If empty, runcore generates an inline config under Dir.
	RNSConfigDir string

	// Dir is runcore's state directory (config, identity, LXMF storage, Reticulum config, contacts, attachments).
	// If empty, defaults to "./.runcore".
	Dir string

	// MessagesDir is a directory for inbound/outbound LXMF message files (messages).
	// Defaults to "<Dir>/storage/messages".
	MessagesDir string

	// ContactsDir is a directory for contacts-related app data.
	// If empty, defaults to "<Dir>/contacts".
	ContactsDir string

	// SendDir is a directory reserved for outbound "send folder" workflows.
	// If empty, runcore does not use it.
	SendDir string

	// DisplayName is embedded into LXMF announce metadata (optional).
	DisplayName string

	// LogLevel uses Reticulum log levels 0..7 (default: 4).
	LogLevel int

	// LogDest is rns.LOG_STDOUT or rns.LOG_FILE (or callback).
	LogDest LogDest

	// DeliveryStampCost sets inbound stamp cost for this node (nil = no requirement).
	DeliveryStampCost *int

	// ResetRNSConfig overwrites generated Dir/rns/config with the embedded template.
	// Has no effect if RNSConfigDir is set.
	ResetRNSConfig bool
}

type Node struct {
	opts Options

	reticulum *rns.Reticulum
	identity  *rns.Identity

	storageDir  string
	contactsDir string
	sendDir     string
	messagesDir string
	meDirMu     sync.RWMutex
	meDir       string

	router          *lxmf.LXMRouter
	deliveryDestIn  *rns.Destination
	profileDestIn   *rns.Destination
	onInbound       func(*lxmf.LXMessage)
	announceMu      sync.Mutex
	announces       map[string]AnnounceEntry
	announceHandler *announceLogger

	outboundMu       sync.Mutex
	outboundMsgFiles map[string]string // msgIDHex -> absolute path in messagesDir

	displayName      string
	avatarPNG        []byte
	avatarHash       []byte
	avatarMTime      int64
	avatarMime       string
	announceStop     chan struct{}
	announceStopOnce sync.Once

	networkResetMu       sync.Mutex
	ifaceStateMu         sync.Mutex
	ifaceOfflineAt       map[string]time.Time
	lastIfaceReset       time.Time
	lastIfacePersistHash [32]byte

	announceInFlight int32
	announceQueued   int32
}

func (n *Node) ProfileName() string {
	if n == nil {
		return ""
	}
	if s := strings.TrimSpace(n.displayName); s != "" {
		return s
	}
	if dir, err := n.findMeContactDir(); err == nil && dir != "" {
		return filepath.Base(dir)
	}
	return "Me"
}

func Start(opts Options) (*Node, error) {
	if opts.Dir == "" {
		if d, err := DefaultRootDir("runcore"); err == nil && d != "" {
			opts.Dir = d
		} else {
			opts.Dir = ".runcore"
		}
	}
	if opts.LogLevel == 0 {
		opts.LogLevel = 4
	}
	if opts.LogDest == nil {
		opts.LogDest = rns.LOG_STDOUT
	}

	if err := os.MkdirAll(opts.Dir, 0o755); err != nil {
		return nil, fmt.Errorf("create runcore dir: %w", err)
	}
	if _, err := EnsureLXMDConfigWithDisplayName(opts.Dir, ""); err != nil {
		return nil, fmt.Errorf("ensure lxmd config: %w", err)
	}
	storageDir := filepath.Join(opts.Dir, "storage")
	if err := os.MkdirAll(storageDir, 0o755); err != nil {
		return nil, fmt.Errorf("create storage dir: %w", err)
	}
	if opts.MessagesDir == "" {
		opts.MessagesDir = filepath.Join(storageDir, "messages")
	}
	if err := os.MkdirAll(opts.MessagesDir, 0o755); err != nil {
		return nil, fmt.Errorf("create messages dir: %w", err)
	}
	rnsConfigDir, err := prepareRNSConfigDir(opts)
	if err != nil {
		return nil, err
	}
	var rnsCfg *string = &rnsConfigDir
	level := opts.LogLevel
	ret, err := rns.NewReticulum(rnsCfg, &level, opts.LogDest, nil, false, nil)
	if err != nil {
		return nil, err
	}

	identityPath := filepath.Join(opts.Dir, "identity")
	var id *rns.Identity
	if _, err := os.Stat(identityPath); err == nil {
		id, err = rns.IdentityFromFile(identityPath)
		if err != nil {
			return nil, fmt.Errorf("load identity: %w", err)
		}
	} else if errors.Is(err, os.ErrNotExist) {
		id, err = rns.NewIdentity()
		if err != nil {
			return nil, fmt.Errorf("create identity: %w", err)
		}
		if err := id.Save(identityPath); err != nil {
			return nil, fmt.Errorf("save identity: %w", err)
		}
	} else {
		return nil, fmt.Errorf("stat identity: %w", err)
	}

	n := &Node{
		opts:             opts,
		reticulum:        ret,
		identity:         id,
		storageDir:       storageDir,
		displayName:      opts.DisplayName,
		announces:        make(map[string]AnnounceEntry),
		ifaceOfflineAt:   make(map[string]time.Time),
		messagesDir:      opts.MessagesDir,
		outboundMsgFiles: make(map[string]string),
	}

	if n.opts.ContactsDir == "" {
		n.opts.ContactsDir = filepath.Join(n.opts.Dir, "contacts")
	}
	n.contactsDir = n.opts.ContactsDir
	_ = os.MkdirAll(n.contactsDir, 0o755)
	rns.Logf(rns.LOG_NOTICE, "runcore: contacts dir=%q", n.contactsDir)
	if dir, err := n.findMeContactDir(); err == nil && dir != "" {
		n.displayName = filepath.Base(dir)
		n.meDirMu.Lock()
		n.meDir = dir
		n.meDirMu.Unlock()
	} else if strings.TrimSpace(n.displayName) == "" {
		n.displayName = "Me"
	}
	_ = UpdateLXMFDisplayName(opts.Dir, n.displayName)

	router, err := lxmf.NewLXMRouter(id, storageDir)
	if err != nil {
		return nil, fmt.Errorf("start lxmf router: %w", err)
	}

	delivery := router.RegisterDeliveryIdentity(id, n.displayName, opts.DeliveryStampCost)
	if delivery == nil {
		router.ExitHandler()
		return nil, errors.New("register delivery identity failed")
	}
	n.router = router
	n.deliveryDestIn = delivery
	if dir, finalName, err := n.ensureMeContactState(n.displayName); err == nil && dir != "" {
		n.displayName = finalName
		n.meDirMu.Lock()
		n.meDir = dir
		n.meDirMu.Unlock()
	} else if err != nil {
		rns.Logf(rns.LOG_WARNING, "ensure me contact state: %v", err)
	}

	n.sendDir = strings.TrimSpace(n.opts.SendDir)
	n.ensureAnnounceStorageDir()
	n.loadAnnouncesFromDisk()

	// Load optional avatar from disk (app-managed).
	_ = n.loadAvatarFromDisk()
	if err := n.initProfileDestination(); err != nil {
		return nil, err
	}
	n.initAnnounceHandler()
	router.RegisterDeliveryCallback(func(m *lxmf.LXMessage) {
		if m == nil {
			return
		}
		n.persistInboundMessage(m)
		if n.onInbound != nil {
			n.onInbound(m)
		}
	})

	// Best-effort periodic announce (helps peers discover us even if multicast is flaky).
	n.startPeriodicAnnounce(60 * time.Second)
	n.startStateWatchdog()
	n.startSendWatchdog()
	n.startInterfaceWatchdog()
	// Persist interface state immediately so the UI can read it right after startup.
	if err := n.persistInterfacesSnapshotToDisk(); err != nil {
		rns.Logf(rns.LOG_DEBUG, "runcore: persist interfaces (startup): %v", err)
	}
	n.AnnounceDeliveryWithReason("start")
	return n, nil
}

func (n *Node) Reticulum() *rns.Reticulum { return n.reticulum }
func (n *Node) Identity() *rns.Identity   { return n.identity }
func (n *Node) Router() *lxmf.LXMRouter   { return n.router }
func (n *Node) DeliveryDestination() *rns.Destination {
	return n.deliveryDestIn
}
func (n *Node) ConfigDir() string   { return n.opts.Dir }
func (n *Node) MessagesDir() string { return n.messagesDir }

// InterfaceStatsJSON returns JSON-encoded Reticulum interface stats (mirrors rns.GetInterfaceStats()).
func (n *Node) InterfaceStatsJSON() string {
	if n == nil || n.reticulum == nil {
		return `{"interfaces":[],"error":"reticulum not started"}`
	}
	stats := n.reticulum.GetInterfaceStats()
	// Ensure stable shape for consumers (UI expects `interfaces`).
	if _, ok := stats["interfaces"]; !ok {
		stats["interfaces"] = []any{}
	}
	if len(stats) == 1 { // only `interfaces` inserted above
		stats["error"] = "no interface stats available"
	}
	b, err := json.Marshal(stats)
	if err != nil {
		return `{"interfaces":[],"error":"marshal failed"}`
	}
	return string(b)
}

type configuredInterfaceEntry struct {
	Name    string `json:"name"`
	Type    string `json:"type,omitempty"`
	Enabled bool   `json:"enabled"`
}

// ConfiguredInterfacesJSON returns interfaces from the Reticulum config file (including disabled ones).
func (n *Node) ConfiguredInterfacesJSON() string {
	if n == nil || n.reticulum == nil || n.reticulum.ConfigPath == "" {
		return `{"interfaces":[],"error":"reticulum not started"}`
	}
	cfg, err := configobj.Load(n.reticulum.ConfigPath)
	if err != nil {
		return `{"interfaces":[],"error":"failed to load reticulum config"}`
	}
	if !cfg.HasSection("interfaces") {
		return `{"interfaces":[]}`
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
	resp := map[string]any{"interfaces": out}
	b, _ := json.Marshal(resp)
	return string(b)
}

func parseTruthyString(s string) bool {
	switch normalizeBoolToken(s) {
	case "1", "y", "yes", "true", "on":
		return true
	default:
		return false
	}
}

func normalizeBoolToken(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

// Close persists LXMF state. Reticulum is a singleton in go-reticulum and has no per-instance shutdown.
func (n *Node) Close() error {
	if n == nil {
		return nil
	}
	if n.announceStop != nil {
		n.announceStopOnce.Do(func() { close(n.announceStop) })
	}
	if n.router != nil {
		n.router.ExitHandler()
	}
	if n.announceHandler != nil {
		rns.DeregisterAnnounceHandler(n.announceHandler)
		n.announceHandler = nil
	}
	return nil
}

// SetInterfaceEnabled updates the Reticulum config and halts/resumes the interface by name.
// Name must match the interface section name under [interfaces] (eg "Default Interface").
func (n *Node) SetInterfaceEnabled(name string, enabled bool) error {
	if n == nil || n.reticulum == nil || n.reticulum.ConfigPath == "" {
		return errors.New("reticulum not started")
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return errors.New("missing interface name")
	}

	cfg, err := configobj.Load(n.reticulum.ConfigPath)
	if err != nil {
		return fmt.Errorf("load reticulum config: %w", err)
	}
	if !cfg.HasSection("interfaces") {
		cfg.Section("interfaces")
	}
	ifcSec := cfg.Section("interfaces").Subsection(name)
	ifcSec.Set("interface_enabled", ternaryString(enabled, "Yes", "No"))
	if err := cfg.Save(n.reticulum.ConfigPath); err != nil {
		return fmt.Errorf("save reticulum config: %w", err)
	}

	// Apply without restart when possible.
	if enabled {
		// Reload is more robust than Resume() here:
		// - works even if the interface is already running (reconnects TCP client interfaces)
		// - re-creates the driver instance after a halt/resume toggle
		if err := n.reticulum.ReloadInterface(name); err != nil {
			return err
		}
		n.AnnounceDeliveryWithReason("interface_enabled")
		return nil
	}
	if err := n.reticulum.HaltInterface(name); err != nil {
		return err
	}
	n.AnnounceDeliveryWithReason("interface_disabled")
	return nil
}

func ternaryString(cond bool, t, f string) string {
	if cond {
		return t
	}
	return f
}

// Restart restarts the LXMF router/delivery destination while keeping the Reticulum singleton.
// This is used by UI clients to re-announce (and to apply any lxmf-side config changes).
func (n *Node) Restart() error {
	if n == nil {
		return errors.New("node not started")
	}
	if n.identity == nil {
		return errors.New("identity missing")
	}
	if n.profileDestIn == nil {
		if err := n.initProfileDestination(); err != nil {
			return err
		}
	}
	if n.storageDir == "" {
		n.storageDir = filepath.Join(n.opts.Dir, "storage")
	}

	if n.router != nil {
		n.router.ExitHandler()
		n.router = nil
		n.deliveryDestIn = nil
	}

	router, err := lxmf.NewLXMRouter(n.identity, n.storageDir)
	if err != nil {
		return fmt.Errorf("start lxmf router: %w", err)
	}
	delivery := router.RegisterDeliveryIdentity(n.identity, n.displayName, n.opts.DeliveryStampCost)
	if delivery == nil {
		router.ExitHandler()
		return errors.New("register delivery identity failed")
	}

	n.router = router
	n.deliveryDestIn = delivery

	router.RegisterDeliveryCallback(func(m *lxmf.LXMessage) {
		if m == nil {
			return
		}
		n.persistInboundMessage(m)
		if n.onInbound != nil {
			n.onInbound(m)
		}
	})

	// Best-effort re-announce on restart.
	n.AnnounceDeliveryWithReason("restart")
	return nil
}

// ResetProfile recreates the local identity and LXMF delivery destination
// without restarting the Reticulum singleton.
func (n *Node) ResetProfile() error {
	if n == nil {
		return errors.New("node not started")
	}
	if strings.TrimSpace(n.opts.Dir) == "" {
		return errors.New("config dir is empty")
	}

	identityPath := filepath.Join(n.opts.Dir, "identity")
	newID, err := rns.NewIdentity()
	if err != nil {
		return fmt.Errorf("create identity: %w", err)
	}
	if err := newID.Save(identityPath); err != nil {
		return fmt.Errorf("save identity: %w", err)
	}

	if dir, err := n.findMeContactDir(); err == nil && dir != "" {
		_ = os.Remove(filepath.Join(dir, meLXMFFileName))
	}

	n.identity = newID
	if err := n.Restart(); err != nil {
		return err
	}
	if dir, finalName, err := n.ensureMeContactDir(n.displayName); err == nil && dir != "" {
		n.displayName = finalName
		n.meDirMu.Lock()
		n.meDir = dir
		n.meDirMu.Unlock()
		if err := n.writeMeLXMFFile(dir, n.DestinationHashHex()); err != nil {
			return err
		}
	}
	_ = UpdateLXMFDisplayName(n.opts.Dir, n.displayName)
	n.AnnounceDeliveryWithReason("profile_reset")
	return nil
}

func (n *Node) SetInboundHandler(cb func(*lxmf.LXMessage)) {
	n.onInbound = cb
}

func (n *Node) DestinationHashHex() string {
	if n.deliveryDestIn == nil {
		return ""
	}
	return hex.EncodeToString(n.deliveryDestIn.Hash())
}

type SendOptions struct {
	Method        byte
	IncludeTicket bool
	StampCost     *int
	Fields        map[any]any
	Title         string
	Content       string
}

func (n *Node) SendHex(destinationHashHex string, msg SendOptions) (*lxmf.LXMessage, error) {
	if n == nil || n.router == nil || n.deliveryDestIn == nil {
		return nil, errors.New("node not started")
	}
	if msg.Method == 0 {
		msg.Method = lxmf.MethodOpportunistic
	}
	destHash, err := hex.DecodeString(destinationHashHex)
	if err != nil {
		return nil, fmt.Errorf("decode destination hash: %w", err)
	}
	if len(destHash) != lxmf.DestinationLength {
		return nil, fmt.Errorf("invalid destination hash length: got %d want %d", len(destHash), lxmf.DestinationLength)
	}

	var remoteIdentity *rns.Identity
	if bytes.Equal(destHash, n.deliveryDestIn.Hash()) {
		remoteIdentity = n.identity
	} else {
		remoteIdentity = rns.IdentityRecall(destHash)
	}
	if remoteIdentity == nil {
		return nil, errors.New("unknown destination identity (need an announce from the peer before you can send)")
	}
	outDest, err := rns.NewDestination(remoteIdentity, rns.DestinationOUT, rns.DestinationSINGLE, lxmf.AppName, "delivery")
	if err != nil {
		return nil, fmt.Errorf("create outbound destination: %w", err)
	}

	lxm, err := lxmf.NewLXMessage(outDest, n.deliveryDestIn, msg.Content, msg.Title, msg.Fields, msg.Method, nil, nil, msg.StampCost, msg.IncludeTicket)
	if err != nil {
		return nil, err
	}

	// Special-case: allow "send to self" even when there are no Reticulum interfaces.
	// We loop the message back into the router as an inbound delivery.
	if bytes.Equal(destHash, n.deliveryDestIn.Hash()) {
		if err := lxm.Pack(false); err != nil {
			return nil, err
		}
		ok := n.router.LXMDelivery(lxm.Packed, rns.DestinationSINGLE, nil, nil, msg.Method, true, false)
		if !ok {
			return nil, errors.New("local loopback delivery failed")
		}
		return lxm, nil
	}

	n.router.HandleOutbound(lxm)
	// Track status transitions to xattr on message files (if a file is registered).
	lxm.RegisterDeliveryCallback(func(m *lxmf.LXMessage) {
		n.setMessageFileStateByMsgID(msgIDHex(m), m.State)
	})
	lxm.RegisterFailedCallback(func(m *lxmf.LXMessage) {
		n.setMessageFileStateByMsgID(msgIDHex(m), m.State)
	})
	return lxm, nil
}

func (n *Node) startInterfaceWatchdog() {
	if n == nil {
		return
	}
	// Watchdog: iOS can leave sockets half-dead after suspend/resume.
	// If all enabled interfaces remain offline for a short window, we hard-reset
	// enabled interfaces (halt+resume) to recreate sockets.
	go func() {
		if err := n.persistInterfacesSnapshotToDisk(); err != nil {
			rns.Logf(rns.LOG_DEBUG, "runcore: persist interfaces: %v", err)
		}
		t := time.NewTicker(2 * time.Second)
		defer t.Stop()
		for {
			select {
			case <-t.C:
				if err := n.persistInterfacesSnapshotToDisk(); err != nil {
					rns.Logf(rns.LOG_DEBUG, "runcore: persist interfaces: %v", err)
				}
				n.maybeResetInterfacesOnStall("watchdog")
			case <-n.announceStop:
				return
			}
		}
	}()
}

func (n *Node) maybeResetInterfacesOnStall(reason string) {
	if n == nil || n.reticulum == nil {
		return
	}
	enabledCfg := n.enabledInterfaceConfigs()
	if len(enabledCfg) == 0 {
		return
	}
	statusByShort, statusByName := n.interfaceOnlineMaps()

	now := time.Now()
	anyOnline := false
	longestOffline := time.Duration(0)

	n.ifaceStateMu.Lock()
	if n.ifaceOfflineAt == nil {
		n.ifaceOfflineAt = make(map[string]time.Time)
	}
	for _, cfg := range enabledCfg {
		name := strings.TrimSpace(cfg.Name)
		if name == "" {
			continue
		}
		on := false
		if v, ok := statusByShort[name]; ok {
			on = v
		} else if v, ok := statusByName[name]; ok {
			on = v
		}
		if on {
			anyOnline = true
			delete(n.ifaceOfflineAt, name)
			continue
		}
		start, ok := n.ifaceOfflineAt[name]
		if !ok {
			n.ifaceOfflineAt[name] = now
			start = now
		}
		d := now.Sub(start)
		if d > longestOffline {
			longestOffline = d
		}
	}
	lastReset := n.lastIfaceReset
	n.ifaceStateMu.Unlock()

	// Trigger reset only if *everything enabled* is offline for a bit.
	if anyOnline {
		return
	}
	if longestOffline < 6*time.Second {
		return
	}
	if !lastReset.IsZero() && time.Since(lastReset) < 12*time.Second {
		return
	}

	n.ifaceStateMu.Lock()
	n.lastIfaceReset = time.Now()
	n.ifaceStateMu.Unlock()
	rns.Logf(rns.LOG_DEBUG, "%s: watchdog triggering interface reset (offline_for=%s)", reason, longestOffline)
	n.resetEnabledInterfaces(reason)
}

func (n *Node) AnnounceDelivery() {
	if n == nil || n.router == nil || n.deliveryDestIn == nil {
		return
	}
	n.AnnounceDeliveryWithReason("manual")
}

func (n *Node) AnnounceDeliveryWithReason(reason string) {
	if n == nil || n.router == nil || n.deliveryDestIn == nil {
		return
	}
	reason = strings.TrimSpace(reason)
	if reason == "" {
		reason = "manual"
	}

	if !atomic.CompareAndSwapInt32(&n.announceInFlight, 0, 1) {
		atomic.StoreInt32(&n.announceQueued, 1)
		return
	}

	stopCh := n.announceStop
	destHex := hex.EncodeToString(n.deliveryDestIn.Hash())

	// Announce can happen early (before interfaces are online) and produces noisy
	// "No interfaces could process the outbound packet" logs. We wait briefly for
	// usable connectivity. If TCP is enabled, we prefer waiting for TCP to be online,
	// but we will still announce over any online enabled interface after a short
	// grace period. (AutoInterface can be unreliable on some networks.)
	go func() {
		// On mobile suspend/resume, sockets can end up half-dead (looks connected but
		// no traffic flows). For iOS we do a hard interface reset: halt all enabled
		// interfaces and bring them up again before we announce.
		if reason == "resume" {
			n.resetEnabledInterfaces(reason)
		}

		deadline := time.Now().Add(20 * time.Second)
		preferDeadline := time.Now().Add(6 * time.Second)
		for {
			if stopCh != nil {
				select {
				case <-stopCh:
					atomic.StoreInt32(&n.announceInFlight, 0)
					return
				default:
				}
			}

			ready, _, _, _ := n.announceReady(preferDeadline)
			if ready {
				// Require a brief stable window (TCP can flap right after connect).
				time.Sleep(1 * time.Second)
				ready2, _, _, _ := n.announceReady(time.Now())
				if ready2 {
					break
				}
			}
			if time.Now().After(deadline) {
				_, enabled, online, offline := n.announceReady(time.Now())
				if len(enabled) == 0 {
					rns.Logf(rns.LOG_NOTICE, "Announce tx dest=%s reason=%s skipped=no_enabled_interfaces", destHex, reason)
				} else {
					rns.Logf(rns.LOG_NOTICE, "Announce tx dest=%s reason=%s skipped=no_usable_interfaces enabled=%s online=%s offline=%s",
						destHex, reason,
						strings.Join(enabled, ","),
						strings.Join(online, ","),
						strings.Join(offline, ","),
					)
				}
				atomic.StoreInt32(&n.announceInFlight, 0)
				return
			}
			time.Sleep(500 * time.Millisecond)
		}

		_, enabled, online, offline := n.announceReady(time.Now())
		if len(enabled) > 0 {
			rns.Logf(rns.LOG_NOTICE, "Announce tx dest=%s reason=%s enabled=%s online=%s offline=%s",
				destHex, reason,
				strings.Join(enabled, ","),
				strings.Join(online, ","),
				strings.Join(offline, ","),
			)
		} else {
			rns.Logf(rns.LOG_NOTICE, "Announce tx dest=%s reason=%s", destHex, reason)
		}

		// Do not rely on lxmf.Router.GetAnnounceAppData() here because it reads
		// unexported internal config. We generate the announce app-data ourselves,
		// matching lxmf.Router.GetAnnounceAppData() format.
		appData := n.announceAppData()

		pkt := n.deliveryDestIn.Announce(appData, false, nil, nil, false)
		if pkt != nil {
			_ = pkt.Send()
		}

		atomic.StoreInt32(&n.announceInFlight, 0)
		if atomic.SwapInt32(&n.announceQueued, 0) == 1 {
			n.AnnounceDeliveryWithReason("queued")
		}
	}()
}

// kickEnabledInterfaces force-reloads enabled interfaces. This is mainly a resilience
// measure for mobile suspend/resume where sockets can become half-open.
func (n *Node) kickEnabledInterfaces() {
	if n == nil || n.reticulum == nil {
		return
	}
	enabledCfg := n.enabledInterfaceConfigs()
	if len(enabledCfg) == 0 {
		return
	}

	statusByShort, statusByName := n.interfaceOnlineMaps()

	for _, cfg := range enabledCfg {
		name := strings.TrimSpace(cfg.Name)
		if name == "" {
			continue
		}
		typ := strings.ToLower(strings.TrimSpace(cfg.Type))
		isTCP := strings.Contains(typ, "tcp")

		on := false
		if v, ok := statusByShort[name]; ok {
			on = v
		} else if v, ok := statusByName[name]; ok {
			on = v
		}

		// Always kick TCP on resume; kick others only if currently offline.
		if !isTCP && on {
			continue
		}
		if err := n.reticulum.ReloadInterface(name); err != nil {
			rns.Logf(rns.LOG_DEBUG, "resume: reload interface failed name=%s err=%v", name, err)
			continue
		}
		rns.Logf(rns.LOG_DEBUG, "resume: reloaded interface name=%s", name)
	}
}

func (n *Node) resetEnabledInterfaces(reason string) {
	if n == nil || n.reticulum == nil {
		return
	}
	// Serialize resets; we do not want concurrent resume events to flap interfaces.
	n.networkResetMu.Lock()
	defer n.networkResetMu.Unlock()

	enabled := n.enabledInterfaceConfigs()
	if len(enabled) == 0 {
		rns.Logf(rns.LOG_DEBUG, "%s: interface reset skipped (no enabled interfaces)", reason)
		return
	}

	names := make([]string, 0, len(enabled))
	for _, cfg := range enabled {
		name := strings.TrimSpace(cfg.Name)
		if name == "" {
			continue
		}
		names = append(names, name)
	}
	if len(names) == 0 {
		rns.Logf(rns.LOG_DEBUG, "%s: interface reset skipped (no valid names)", reason)
		return
	}

	rns.Logf(rns.LOG_DEBUG, "%s: interface reset begin enabled=%s", reason, strings.Join(names, ","))

	// Halt first (best-effort). This tears down sockets and stops per-interface goroutines.
	for _, name := range names {
		if err := n.reticulum.HaltInterface(name); err != nil {
			rns.Logf(rns.LOG_DEBUG, "%s: halt interface failed name=%s err=%v", reason, name, err)
		} else {
			rns.Logf(rns.LOG_DEBUG, "%s: halted interface name=%s", reason, name)
		}
	}

	// Small grace period to let the OS release sockets after suspend.
	time.Sleep(400 * time.Millisecond)

	// Resume in original order (best-effort).
	for _, name := range names {
		if err := n.reticulum.ResumeInterface(name); err != nil {
			rns.Logf(rns.LOG_DEBUG, "%s: resume interface failed name=%s err=%v", reason, name, err)
		} else {
			rns.Logf(rns.LOG_DEBUG, "%s: resumed interface name=%s", reason, name)
		}
	}

	rns.Logf(rns.LOG_DEBUG, "%s: interface reset end", reason)
}

func (n *Node) announceReady(preferDeadline time.Time) (bool, []string, []string, []string) {
	enabledCfg := n.enabledInterfaceConfigs()
	if len(enabledCfg) == 0 {
		if n.hasAnyOnlineInterface() {
			return true, nil, nil, nil
		}
		return false, nil, nil, nil
	}

	statusByShort, statusByName := n.interfaceOnlineMaps()
	enabled := make([]string, 0, len(enabledCfg))
	online := make([]string, 0, len(enabledCfg))
	offline := make([]string, 0, len(enabledCfg))

	hasTCPEnabled := false
	hasTCPOnline := false

	for _, cfg := range enabledCfg {
		name := cfg.Name
		enabled = append(enabled, name)

		typ := strings.ToLower(strings.TrimSpace(cfg.Type))
		isTCP := strings.Contains(typ, "tcp")
		if isTCP {
			hasTCPEnabled = true
		}

		on := false
		if v, ok := statusByShort[name]; ok {
			on = v
		} else if v, ok := statusByName[name]; ok {
			on = v
		}
		if on {
			online = append(online, name)
			if isTCP {
				hasTCPOnline = true
			}
		} else {
			offline = append(offline, name)
		}
	}

	if len(online) == 0 {
		return false, enabled, online, offline
	}

	// Prefer waiting for TCP if enabled (it is usually the path to the wider network).
	if hasTCPEnabled && !hasTCPOnline && time.Now().Before(preferDeadline) {
		return false, enabled, online, offline
	}

	return true, enabled, online, offline
}

func (n *Node) enabledInterfaceConfigs() []configuredInterfaceEntry {
	if n == nil || n.reticulum == nil || n.reticulum.ConfigPath == "" {
		return nil
	}
	cfg, err := configobj.Load(n.reticulum.ConfigPath)
	if err != nil {
		return nil
	}
	if !cfg.HasSection("interfaces") {
		return nil
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
		if enabled {
			out = append(out, configuredInterfaceEntry{Name: name, Type: typ, Enabled: true})
		}
	}
	return out
}

func (n *Node) interfaceOnlineMaps() (map[string]bool, map[string]bool) {
	statusByShort := map[string]bool{}
	statusByName := map[string]bool{}
	if n == nil || n.reticulum == nil {
		return statusByShort, statusByName
	}
	stats := n.reticulum.GetInterfaceStats()
	raw := stats["interfaces"]
	if raw == nil {
		return statusByShort, statusByName
	}

	extract := func(entry map[string]any) {
		var (
			short string
			name  string
		)
		if v, ok := entry["short_name"].(string); ok {
			short = strings.TrimSpace(v)
		}
		if v, ok := entry["name"].(string); ok {
			name = strings.TrimSpace(v)
		}
		status, _ := entry["status"].(bool)
		if short != "" {
			statusByShort[short] = status
		}
		if name != "" {
			statusByName[name] = status
		}
	}

	switch v := raw.(type) {
	case []map[string]any:
		for _, entry := range v {
			extract(entry)
		}
	case []any:
		for _, item := range v {
			entry, ok := item.(map[string]any)
			if !ok {
				continue
			}
			extract(entry)
		}
	}
	return statusByShort, statusByName
}

func (n *Node) hasAnyOnlineInterface() bool {
	if n == nil || n.reticulum == nil {
		return false
	}
	statusByShort, statusByName := n.interfaceOnlineMaps()
	for _, v := range statusByShort {
		if v {
			return true
		}
	}
	for _, v := range statusByName {
		if v {
			return true
		}
	}
	return false
}

func (n *Node) startPeriodicAnnounce(interval time.Duration) {
	if n == nil {
		return
	}
	if interval <= 0 {
		return
	}
	if n.announceStop != nil {
		return
	}
	n.announceStop = make(chan struct{})
	t := time.NewTicker(interval)
	go func() {
		defer t.Stop()
		for {
			select {
			case <-t.C:
				n.AnnounceDeliveryWithReason("periodic")
			case <-n.announceStop:
				return
			}
		}
	}()
}

func (n *Node) startStateWatchdog() {
	if n == nil {
		return
	}
	if n.announceStop == nil {
		n.announceStop = make(chan struct{})
	}

	type snapshot struct {
		meDir          string
		name           string
		avatarHashHex  string
		avatarInit     bool
		configMTime    int64
		rnsConfigMTime int64
	}

	go func() {
		var st snapshot
		configPath := filepath.Join(n.opts.Dir, "config")
		rnsConfigPath := filepath.Join(n.opts.Dir, "rns", "config")
		rnsDir := filepath.Dir(rnsConfigPath)

		scan := func() {
			// Track rename of contacts/<me> (xattr-tagged) and announce when it changes.
			if dir, err := n.findMeContactDir(); err == nil && dir != "" {
				name := filepath.Base(dir)
				if ensuredDir, ensuredName, ensureErr := n.ensureMeContactState(name); ensureErr == nil && ensuredDir != "" {
					dir = ensuredDir
					name = ensuredName
				} else if ensureErr != nil {
					rns.Logf(rns.LOG_WARNING, "ensure me contact state: %v", ensureErr)
				}
				if st.meDir == "" {
					st.meDir = dir
					st.name = name
				}
				if dir != st.meDir || (name != "" && name != st.name) {
					st.meDir = dir
					st.name = name
					if name != "" && name != n.displayName {
						n.displayName = name
						_ = UpdateLXMFDisplayName(n.opts.Dir, n.displayName)
						n.AnnounceDeliveryWithReason("display_name_changed")
					}
				}
			} else {
				dir, finalName, ensureErr := n.ensureMeContactState(n.displayName)
				if ensureErr == nil && dir != "" {
					st.meDir = dir
					st.name = finalName
					n.displayName = finalName
					n.meDirMu.Lock()
					n.meDir = dir
					n.meDirMu.Unlock()
					_ = UpdateLXMFDisplayName(n.opts.Dir, n.displayName)
					n.AnnounceDeliveryWithReason("me_contact_restored")
				}
			}

			// Track avatar changes on disk and announce when changed.
			n.refreshAvatarFromDisk()
			newAvatar := hex.EncodeToString(n.avatarHash)
			if !st.avatarInit {
				st.avatarHashHex = newAvatar
				st.avatarInit = true
			} else if newAvatar != st.avatarHashHex {
				st.avatarHashHex = newAvatar
				n.AnnounceDeliveryWithReason("avatar_changed")
			}

			// Track config changes (best-effort) and announce when modified.
			if info, err := os.Stat(configPath); err == nil {
				mt := info.ModTime().Unix()
				if st.configMTime == 0 {
					st.configMTime = mt
				} else if mt != st.configMTime {
					st.configMTime = mt
					n.AnnounceDeliveryWithReason("config_changed")
				}
			}
			if info, err := os.Stat(rnsConfigPath); err == nil {
				mt := info.ModTime().Unix()
				if st.rnsConfigMTime == 0 {
					st.rnsConfigMTime = mt
				} else if mt != st.rnsConfigMTime {
					st.rnsConfigMTime = mt
					n.AnnounceDeliveryWithReason("rns_config_changed")
				}
			}
		}

		// Prefer fsnotify; fallback to polling if watcher cannot start.
		w, err := fsnotify.NewWatcher()
		if err != nil {
			t := time.NewTicker(10 * time.Second)
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

		// Always keep a light poll even when fsnotify is active.
		// Some filesystems (notably iCloud on Apple platforms) can miss rename events.
		poll := time.NewTicker(10 * time.Second)
		defer poll.Stop()

		// Watch directories (watching files directly is less portable).
		_ = w.Add(n.contactsDir)
		_ = w.Add(n.opts.Dir)
		_ = w.Add(rnsDir)

		var debounceMu sync.Mutex
		var debounce *time.Timer
		trigger := func() {
			debounceMu.Lock()
			defer debounceMu.Unlock()
			if debounce != nil {
				debounce.Stop()
			}
			debounce = time.AfterFunc(500*time.Millisecond, scan)
		}

		// Initial scan so state is consistent (and we don't announce spuriously).
		scan()

		for {
			select {
			case <-n.announceStop:
				return
			case <-poll.C:
				scan()
			case _, ok := <-w.Events:
				if !ok {
					return
				}
				trigger()
			case _, ok := <-w.Errors:
				if !ok {
					return
				}
				// Watcher errors are common on some FS (notably iCloud); we still keep a light poll.
				t := time.NewTicker(15 * time.Second)
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

// SetDisplayName renames the "me" contact folder and updates the profile name.
func (n *Node) SetDisplayName(name string) error {
	if n == nil || n.deliveryDestIn == nil {
		return errors.New("node not started")
	}
	dir, finalName, err := n.ensureMeContactState(name)
	if err != nil {
		return err
	}
	n.displayName = finalName
	if dir != "" {
		n.meDirMu.Lock()
		n.meDir = dir
		n.meDirMu.Unlock()
	}
	_ = UpdateLXMFDisplayName(n.opts.Dir, n.displayName)
	n.AnnounceDeliveryWithReason("display_name_changed")
	return nil
}

func (n *Node) SetAvatarPNG(png []byte) error {
	return n.SetAvatarImage("", png)
}

func (n *Node) SetAvatarHEIC(heic []byte) error {
	return n.SetAvatarImage("image/heic", heic)
}

func (n *Node) SetAvatarImage(mime string, data []byte) error {
	if n == nil {
		return errors.New("node not started")
	}
	if len(data) == 0 {
		return errors.New("empty avatar")
	}
	mime = strings.TrimSpace(mime)
	if mime == "" {
		mime = detectAvatarMime(data)
	}
	if mime == "" {
		return errors.New("unknown avatar mime")
	}
	sum := sha256.Sum256(data)
	n.avatarPNG = append([]byte(nil), data...)
	n.avatarHash = append([]byte(nil), sum[:16]...)
	n.avatarMTime = time.Now().Unix()
	n.avatarMime = mime
	return n.saveAvatarToDisk()
}

func (n *Node) ClearAvatar() error {
	if n == nil {
		return errors.New("node not started")
	}
	n.avatarPNG = nil
	n.avatarHash = nil
	n.avatarMTime = 0
	n.avatarMime = ""
	for _, p := range n.avatarAllPaths() {
		_ = os.Remove(p)
	}
	return nil
}

func (n *Node) refreshAvatarFromDisk() {
	if n == nil {
		return
	}
	if err := n.loadAvatarFromDisk(); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			n.avatarPNG = nil
			n.avatarHash = nil
			n.avatarMTime = 0
			n.avatarMime = ""
		}
	}
}

func (n *Node) announceAppData() []byte {
	n.refreshAvatarFromDisk()
	// Mirrors lxmf.Router.GetAnnounceAppData(): msgpack([display_name_bytes, stamp_cost?])
	var displayNameBytes []byte
	if n.displayName != "" {
		displayNameBytes = []byte(n.displayName)
	}
	var stampCost any
	if n.opts.DeliveryStampCost != nil && *n.opts.DeliveryStampCost > 0 && *n.opts.DeliveryStampCost < 255 {
		stampCost = *n.opts.DeliveryStampCost
	}

	var avatar any
	if len(n.avatarHash) > 0 {
		mime := n.avatarMime
		if mime == "" {
			mime = "image/png"
		}
		avatar = map[any]any{
			"h": n.avatarHash,     // bytes
			"t": mime,             // mime
			"s": len(n.avatarPNG), // size
			"u": n.avatarMTime,    // updated (unix)
		}
	}

	data, err := umsgpack.Packb([]any{displayNameBytes, stampCost, avatar})
	if err != nil {
		return nil
	}
	return data
}

func (n *Node) avatarPath() string {
	ext := avatarExtForMime(n.avatarMime)
	return filepath.Join(n.avatarStoreDir(), "avatar"+ext)
}

func (n *Node) avatarAllPaths() []string {
	base := n.avatarStoreDir()
	return []string{
		filepath.Join(base, "avatar.png"),
		filepath.Join(base, "avatar.jpg"),
		filepath.Join(base, "avatar.jpeg"),
		filepath.Join(base, "avatar.heic"),
		// Legacy formats:
		filepath.Join(base, "avatar.bin"),
	}
}

func (n *Node) loadAvatarFromDisk() error {
	base := n.avatarStoreDir()
	var path string
	var b []byte
	for _, candidate := range []string{
		filepath.Join(base, "avatar.png"),
		filepath.Join(base, "avatar.jpg"),
		filepath.Join(base, "avatar.jpeg"),
		filepath.Join(base, "avatar.heic"),
		// Legacy (no extension).
		filepath.Join(base, "avatar.bin"),
	} {
		if cb, err := os.ReadFile(candidate); err == nil && len(cb) > 0 {
			path = candidate
			b = cb
			break
		}
	}
	if path == "" || len(b) == 0 {
		return os.ErrNotExist
	}

	sum := sha256.Sum256(b)
	n.avatarPNG = b
	n.avatarHash = append([]byte(nil), sum[:16]...)
	if st, err := os.Stat(path); err == nil {
		n.avatarMTime = st.ModTime().Unix()
	}

	ext := strings.ToLower(filepath.Ext(path))
	n.avatarMime = avatarMimeForExt(ext)
	if n.avatarMime == "" {
		n.avatarMime = detectAvatarMime(b)
	}
	if n.avatarMime == "" {
		return errors.New("unknown avatar mime")
	}
	return nil
}

func (n *Node) saveAvatarToDisk() error {
	if len(n.avatarPNG) == 0 {
		return nil
	}
	target := n.avatarPath()
	if err := os.WriteFile(target, n.avatarPNG, 0o644); err != nil {
		return err
	}
	return nil
}

func (n *Node) avatarStoreDir() string {
	if n == nil {
		return ""
	}
	if dir, err := n.findMeContactDir(); err == nil && dir != "" {
		return dir
	}
	if dir, final, err := n.ensureMeContactState(n.displayName); err == nil && dir != "" {
		if final != "" {
			n.displayName = final
		}
		return dir
	}
	return n.opts.Dir
}

func avatarExtForMime(mime string) string {
	switch strings.ToLower(strings.TrimSpace(mime)) {
	case "image/png":
		return ".png"
	case "image/jpeg", "image/jpg":
		return ".jpg"
	case "image/heic":
		return ".heic"
	default:
		return ".bin"
	}
}

func avatarMimeForExt(ext string) string {
	switch strings.ToLower(strings.TrimSpace(ext)) {
	case ".png":
		return "image/png"
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".heic":
		return "image/heic"
	default:
		return ""
	}
}

func detectAvatarMime(data []byte) string {
	if len(data) >= 8 && bytes.Equal(data[:8], []byte{0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a}) {
		return "image/png"
	}
	if len(data) >= 3 && data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff {
		return "image/jpeg"
	}
	if len(data) >= 12 && bytes.Equal(data[4:8], []byte("ftyp")) {
		brand := string(data[8:12])
		switch brand {
		case "heic", "heix", "hevc", "hevx", "mif1", "msf1":
			return "image/heic"
		}
	}
	return ""
}

func readFileOrNil(path string) []byte {
	if path == "" {
		return nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	return b
}

func (n *Node) WaitForIdentityHex(destinationHashHex string, timeout time.Duration) (*rns.Identity, error) {
	destHash, err := hex.DecodeString(destinationHashHex)
	if err != nil {
		return nil, fmt.Errorf("decode destination hash: %w", err)
	}
	if len(destHash) != lxmf.DestinationLength {
		return nil, fmt.Errorf("invalid destination hash length: got %d want %d", len(destHash), lxmf.DestinationLength)
	}

	// Fast-path: allow "send to self" without requiring any announce/recall.
	if n != nil && n.deliveryDestIn != nil && bytes.Equal(destHash, n.deliveryDestIn.Hash()) {
		if n.identity != nil {
			return n.identity, nil
		}
	}

	// If we don't have the identity yet, try querying the network for a path/identity.
	// This makes "add contact by hash → send" work without requiring a prior announce.
	if rns.IdentityRecall(destHash) == nil {
		rns.TransportRequestPath(destHash)
	}

	deadline := time.Now().Add(timeout)
	for {
		if id := rns.IdentityRecall(destHash); id != nil {
			return id, nil
		}
		if timeout > 0 && time.Now().After(deadline) {
			return nil, errors.New("timeout waiting for destination identity")
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func prepareRNSConfigDir(opts Options) (string, error) {
	if opts.RNSConfigDir != "" {
		return opts.RNSConfigDir, nil
	}

	cfgDir := filepath.Join(opts.Dir, "rns")
	if err := os.MkdirAll(cfgDir, 0o755); err != nil {
		return "", fmt.Errorf("create rns config dir: %w", err)
	}
	cfgPath := filepath.Join(cfgDir, "config")

	template := []byte(defaultInlineRNSConfig(opts.LogLevel))

	if opts.ResetRNSConfig {
		if err := os.WriteFile(cfgPath, template, 0o644); err != nil {
			return "", fmt.Errorf("overwrite rns config: %w", err)
		}
		_ = ensureRNSAutoInterfaceDefaults(cfgPath)
		return cfgDir, nil
	}

	if _, err := os.Stat(cfgPath); err == nil {
		// Config exists: treat it as user-owned; only fill missing defaults.
		_ = ensureRNSAutoInterfaceDefaults(cfgPath)
		return cfgDir, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("stat rns config: %w", err)
	}

	if err := os.WriteFile(cfgPath, template, 0o644); err != nil {
		return "", fmt.Errorf("write rns config: %w", err)
	}
	_ = ensureRNSAutoInterfaceDefaults(cfgPath)

	return cfgDir, nil
}

// ensureRNSAutoInterfaceDefaults fills in safe defaults for the generated AutoInterface
// without clobbering explicit user config.
func ensureRNSAutoInterfaceDefaults(cfgPath string) error {
	cfg, err := configobj.Load(cfgPath)
	if err != nil {
		return err
	}
	if !cfg.HasSection("interfaces") {
		return nil
	}
	ifc := cfg.Section("interfaces").Subsection("Default Interface")
	typ, _ := ifc.Get("type")
	if !strings.EqualFold(strings.TrimSpace(typ), "AutoInterface") {
		return nil
	}
	changed := false
	if v, ok := ifc.Get("devices"); !ok || strings.TrimSpace(v) == "" {
		devs := autoInterfaceDefaultDevices()
		if len(devs) > 0 {
			ifc.Set("devices", strings.Join(devs, ", "))
			changed = true
		}
	} else {
		// Some environments (notably Mac Catalyst with VPNs) expose many virtual interfaces
		// (eg. utun*, awdl0) that tend to break multicast discovery. If the user config
		// already pins devices, sanitize the list by removing obviously-bad defaults.
		parts := strings.Split(v, ",")
		filtered := make([]string, 0, len(parts))
		for _, p := range parts {
			name := strings.TrimSpace(p)
			if name == "" {
				continue
			}
			if strings.HasPrefix(name, "utun") || name == "awdl0" {
				continue
			}
			filtered = append(filtered, name)
		}
		if len(filtered) == 0 {
			filtered = autoInterfaceDefaultDevices()
		}
		normalized := strings.Join(filtered, ", ")
		if strings.TrimSpace(normalized) != strings.TrimSpace(v) && normalized != "" {
			ifc.Set("devices", normalized)
			changed = true
		}
	}
	if v, ok := ifc.Get("ingress_control"); !ok || strings.TrimSpace(v) == "" {
		ifc.Set("ingress_control", "no")
		changed = true
	}
	if !changed {
		return nil
	}
	return cfg.Save(cfgPath)
}

func autoInterfaceDefaultDevices() []string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	out := make([]string, 0, 4)
	seen := map[string]bool{}
	for _, nif := range ifaces {
		if (nif.Flags & net.FlagUp) == 0 {
			continue
		}
		name := strings.TrimSpace(nif.Name)
		if name == "" || seen[name] {
			continue
		}

		// Conservative allowlist: typical Wi‑Fi/Ethernet names across platforms.
		// If nothing matches, we fall back to AutoInterface's own behaviour.
		switch {
		case strings.HasPrefix(name, "en"), // macOS/iOS
			strings.HasPrefix(name, "eth"),    // linux
			strings.HasPrefix(name, "wlan"),   // linux
			strings.HasPrefix(name, "wlp"),    // linux (systemd)
			strings.HasPrefix(name, "wl"),     // some BSDs
			strings.HasPrefix(name, "pdp_ip"): // iOS cellular
			seen[name] = true
			out = append(out, name)
		}
	}
	sort.Strings(out)
	return out
}

func defaultInlineRNSConfig(logLevel int) string {
	if logLevel < 0 {
		logLevel = 0
	}
	if logLevel > 7 {
		logLevel = 7
	}
	return fmt.Sprintf(`[reticulum]
	enable_transport = False
	share_instance = False
	instance_name = default

	[logging]
	loglevel = %d

	[interfaces]
	  [[Default Interface]]
	    type = AutoInterface
	    interface_enabled = Yes
	    ingress_control = no

	  [[TCP Client Interface]]
	    type = TCPClientInterface
	    interface_enabled = Yes
	    target_host = reticulum.betweentheborders.com
	    target_port = 4242
	`, logLevel)
}
