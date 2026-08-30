package runcore

import (
	"encoding/hex"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/svanichkin/go-reticulum/rns"
	umsgpack "github.com/svanichkin/go-reticulum/rns/vendor"
)

// LXST telephony constants mirror LXST.Primitives.Telephony.
const (
	LXSTStatusBusy        = 0x00
	LXSTStatusRejected    = 0x01
	LXSTStatusCalling     = 0x02
	LXSTStatusAvailable   = 0x03
	LXSTStatusRinging     = 0x04
	LXSTStatusConnecting  = 0x05
	LXSTStatusEstablished = 0x06
	LXSTPreferredProfile  = 0xFF

	LXSTProfileQualityMedium = 0x40

	LXSTCodecRaw    = 0x00
	LXSTCodecOpus   = 0x01
	LXSTCodecCodec2 = 0x02
)

const (
	lxstFieldSignalling = 0x00
	lxstFieldFrames     = 0x01
)

// Telephone implements LXST telephony transport. The embedding app supplies
// capture, codec processing and playback through FrameCallback and SendFrame.
type Telephone struct {
	node        *Node
	destination *rns.Destination

	mu         sync.Mutex
	activeLink *rns.Link
	incoming   bool
	answered   bool
	identified bool
	profile    int
	remoteHash string
	closed     bool

	StateCallback func(status int, remoteIdentityHash string)
	FrameCallback func(codec int, frame []byte)
}

func NewTelephone(node *Node) (*Telephone, error) {
	if node == nil || node.Identity() == nil {
		return nil, errors.New("LXST telephone requires a running Reticulum identity")
	}
	destination, err := rns.NewDestination(node.Identity(), rns.DestinationIN, rns.DestinationSINGLE, "lxst", "telephony")
	if err != nil {
		return nil, fmt.Errorf("create LXST telephony destination: %w", err)
	}
	_ = destination.SetProofStrategy(rns.DestinationPROVE_NONE)
	t := &Telephone{node: node, destination: destination, profile: LXSTProfileQualityMedium}
	destination.SetLinkEstablishedCallback(t.incomingLinkEstablished)
	return t, nil
}

func (t *Telephone) Announce() {
	if t != nil && t.destination != nil {
		t.destination.Announce(nil, false, nil, nil, true)
	}
}

// Call accepts an announced LXMF destination hash, resolves its identity, and
// then opens the identity's lxst.telephony destination, as Sideband does.
func (t *Telephone) Call(destinationHashHex string, profile int) error {
	if t == nil {
		return errors.New("LXST telephone is unavailable")
	}
	t.mu.Lock()
	if t.closed || t.activeLink != nil {
		t.mu.Unlock()
		return errors.New("another call is already active")
	}
	t.profile = normalizedLXSTProfile(profile)
	t.incoming, t.answered, t.identified = false, false, false
	t.mu.Unlock()

	remoteIdentity, err := t.resolveRemoteIdentity(destinationHashHex, 15*time.Second)
	if err != nil {
		return fmt.Errorf("resolve remote identity: %w", err)
	}
	callDestination, err := rns.NewDestination(remoteIdentity, rns.DestinationOUT, rns.DestinationSINGLE, "lxst", "telephony")
	if err != nil {
		return fmt.Errorf("create remote LXST destination: %w", err)
	}
	if !rns.TransportHasPath(callDestination.Hash()) {
		rns.TransportRequestPath(callDestination.Hash())
		deadline := time.Now().Add(20 * time.Second)
		for !rns.TransportHasPath(callDestination.Hash()) && time.Now().Before(deadline) {
			time.Sleep(100 * time.Millisecond)
		}
	}
	if !rns.TransportHasPath(callDestination.Hash()) {
		return errors.New("no Reticulum path to the remote LXST telephone")
	}

	link, err := rns.NewOutgoingLink(callDestination, rns.LinkModeDefault, t.outgoingLinkEstablished, t.linkClosed)
	if err != nil {
		return fmt.Errorf("establish LXST link: %w", err)
	}
	t.mu.Lock()
	if t.closed || t.activeLink != nil {
		t.mu.Unlock()
		link.Teardown()
		return errors.New("call state changed while opening LXST link")
	}
	t.activeLink = link
	t.remoteHash = hex.EncodeToString(remoteIdentity.Hash)
	t.mu.Unlock()
	t.emitState(LXSTStatusCalling)
	return nil
}

// resolveRemoteIdentity accepts either an announced application destination
// hash (such as an LXMF peer) or the identity hash shown by Sideband.
func (t *Telephone) resolveRemoteIdentity(value string, timeout time.Duration) (*rns.Identity, error) {
	hash, err := hex.DecodeString(value)
	if err != nil || len(hash) != 16 {
		return nil, errors.New("identity or destination hash must be 32 hexadecimal characters")
	}
	resolve := func() *rns.Identity {
		if identity := rns.IdentityRecall(hash); identity != nil {
			return identity
		}
		return rns.IdentityRecall(hash, true)
	}
	if identity := resolve(); identity != nil {
		return identity, nil
	}
	// Request both interpretations. For an LXMF destination hash, the original
	// value resolves its announce. For a Sideband identity hash, Reticulum can
	// deterministically derive the lxst.telephony destination and request its
	// announce, which supplies the public key needed to establish the link.
	lxstDestinationHash := rns.HashFromNameAndIdentity("lxst.telephony", hash)
	rns.TransportRequestPath(hash)
	if len(lxstDestinationHash) > 0 {
		rns.TransportRequestPath(lxstDestinationHash)
	}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if identity := resolve(); identity != nil {
			return identity, nil
		}
		if len(lxstDestinationHash) > 0 {
			if identity := rns.IdentityRecall(lxstDestinationHash); identity != nil {
				return identity, nil
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	return nil, errors.New("no announced Sideband identity was found for that hash")
}

func (t *Telephone) Answer() error {
	t.mu.Lock()
	link := t.activeLink
	valid := link != nil && t.incoming && !t.answered
	if valid {
		t.answered = true
	}
	t.mu.Unlock()
	if !valid {
		return errors.New("there is no incoming LXST call to answer")
	}
	if err := t.sendSignal(LXSTStatusConnecting, link); err != nil {
		return err
	}
	if err := t.sendSignal(LXSTStatusEstablished, link); err != nil {
		return err
	}
	t.emitState(LXSTStatusEstablished)
	return nil
}

func (t *Telephone) Hangup(reject bool) {
	if t == nil {
		return
	}
	t.mu.Lock()
	link := t.activeLink
	shouldReject := reject && link != nil && t.incoming && !t.answered
	t.activeLink = nil
	t.incoming, t.answered, t.identified = false, false, false
	t.mu.Unlock()
	if link != nil {
		if shouldReject {
			_ = t.sendSignal(LXSTStatusRejected, link)
		}
		link.Teardown()
	}
	t.emitState(LXSTStatusAvailable)
}

func (t *Telephone) Close() {
	if t == nil {
		return
	}
	t.mu.Lock()
	t.closed = true
	t.mu.Unlock()
	t.Hangup(false)
}

func (t *Telephone) SendFrame(codec int, frame []byte) error {
	t.mu.Lock()
	link := t.activeLink
	established := link != nil && t.answered
	t.mu.Unlock()
	if !established {
		return errors.New("LXST call is not established")
	}
	if codec != LXSTCodecRaw && codec != LXSTCodecOpus && codec != LXSTCodecCodec2 {
		return errors.New("unsupported LXST codec")
	}
	payload := append([]byte{byte(codec)}, frame...)
	packed, err := umsgpack.Packb(map[any]any{lxstFieldFrames: payload})
	if err != nil {
		return err
	}
	packet := rns.NewPacket(link, packed, rns.WithCreateReceipt(false))
	if packet == nil || (packet.Send() == nil && !packet.Sent) {
		return errors.New("LXST frame transmission failed")
	}
	return nil
}

func (t *Telephone) incomingLinkEstablished(link *rns.Link) {
	t.mu.Lock()
	busy := t.closed || t.activeLink != nil
	t.mu.Unlock()
	if busy {
		_ = t.sendSignal(LXSTStatusBusy, link)
		link.Teardown()
		return
	}
	link.SetPacketCallback(t.packetReceived)
	link.SetLinkClosedCallback(t.linkClosed)
	link.SetRemoteIdentifiedCallback(t.callerIdentified)
	_ = t.sendSignal(LXSTStatusAvailable, link)
}

func (t *Telephone) callerIdentified(link *rns.Link, identity *rns.Identity) {
	if identity == nil {
		link.Teardown()
		return
	}
	t.mu.Lock()
	if t.closed || t.activeLink != nil {
		t.mu.Unlock()
		_ = t.sendSignal(LXSTStatusBusy, link)
		link.Teardown()
		return
	}
	t.activeLink = link
	t.incoming, t.answered, t.identified = true, false, true
	t.profile = LXSTProfileQualityMedium
	t.remoteHash = hex.EncodeToString(identity.Hash)
	t.mu.Unlock()
	_ = t.sendSignal(LXSTStatusRinging, link)
	t.emitState(LXSTStatusRinging)
}

func (t *Telephone) outgoingLinkEstablished(link *rns.Link) {
	link.SetPacketCallback(t.packetReceived)
	link.SetLinkClosedCallback(t.linkClosed)
	// Identify as soon as the encrypted link is ready. LXST receivers send an
	// AVAILABLE signal first, but on slow interfaces that first packet can reach
	// us while the outgoing packet callback is still being installed. Waiting
	// exclusively for it leaves the receiver unable to identify or ring for the
	// caller. The later AVAILABLE handler remains as a compatibility fallback.
	link.Identify(t.node.Identity())
	t.mu.Lock()
	if link == t.activeLink {
		t.identified = true
	}
	t.mu.Unlock()
}

func (t *Telephone) linkClosed(link *rns.Link) {
	t.mu.Lock()
	if link != t.activeLink {
		t.mu.Unlock()
		return
	}
	t.activeLink = nil
	t.incoming, t.answered, t.identified = false, false, false
	t.mu.Unlock()
	t.emitState(LXSTStatusAvailable)
}

func (t *Telephone) packetReceived(data []byte, _ *rns.Packet) {
	var unpacked map[any]any
	if err := umsgpack.Unpackb(data, &unpacked); err != nil {
		return
	}
	if value, ok := mapIntegerValue(unpacked, lxstFieldSignalling); ok {
		for _, signal := range integerList(value) {
			t.handleSignal(signal)
		}
	}
	if value, ok := mapIntegerValue(unpacked, lxstFieldFrames); ok {
		for _, frame := range byteFrames(value) {
			if len(frame) < 2 || t.FrameCallback == nil {
				continue
			}
			t.FrameCallback(int(frame[0]), append([]byte(nil), frame[1:]...))
		}
	}
}

func (t *Telephone) handleSignal(signal int) {
	t.mu.Lock()
	link, incoming, answered := t.activeLink, t.incoming, t.answered
	t.mu.Unlock()
	if link == nil || (incoming && !answered && signal < LXSTPreferredProfile) {
		return
	}
	switch signal {
	case LXSTStatusBusy, LXSTStatusRejected:
		t.Hangup(false)
		t.emitState(signal)
	case LXSTStatusAvailable:
		t.mu.Lock()
		alreadyIdentified := t.identified
		if !alreadyIdentified {
			t.identified = true
		}
		t.mu.Unlock()
		if !alreadyIdentified {
			link.Identify(t.node.Identity())
		}
		t.emitState(signal)
	case LXSTStatusRinging:
		_ = t.sendSignal(LXSTPreferredProfile+t.profile, link)
		t.emitState(signal)
	case LXSTStatusConnecting:
		_ = t.sendSignal(LXSTStatusEstablished, link)
	case LXSTStatusEstablished:
		t.mu.Lock()
		t.answered = true
		t.mu.Unlock()
		t.emitState(signal)
	default:
		if signal >= LXSTPreferredProfile {
			t.mu.Lock()
			t.profile = normalizedLXSTProfile(signal - LXSTPreferredProfile)
			t.mu.Unlock()
		}
	}
}

func (t *Telephone) sendSignal(signal int, link *rns.Link) error {
	packed, err := umsgpack.Packb(map[any]any{lxstFieldSignalling: []any{signal}})
	if err != nil {
		return err
	}
	packet := rns.NewPacket(link, packed, rns.WithCreateReceipt(false))
	if packet == nil || (packet.Send() == nil && !packet.Sent) {
		return errors.New("LXST signalling transmission failed")
	}
	return nil
}

func (t *Telephone) emitState(status int) {
	if t.StateCallback == nil {
		return
	}
	t.mu.Lock()
	remote := t.remoteHash
	t.mu.Unlock()
	t.StateCallback(status, remote)
}

func normalizedLXSTProfile(profile int) int {
	switch profile {
	case 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80:
		return profile
	default:
		return LXSTProfileQualityMedium
	}
}

func mapIntegerValue(values map[any]any, wanted int) (any, bool) {
	for key, value := range values {
		if integerValue(key) == wanted {
			return value, true
		}
	}
	return nil, false
}

func integerList(value any) []int {
	if values, ok := value.([]any); ok {
		result := make([]int, 0, len(values))
		for _, entry := range values {
			result = append(result, integerValue(entry))
		}
		return result
	}
	return []int{integerValue(value)}
}

func integerValue(value any) int {
	switch number := value.(type) {
	case int:
		return number
	case int8:
		return int(number)
	case int16:
		return int(number)
	case int32:
		return int(number)
	case int64:
		return int(number)
	case uint:
		return int(number)
	case uint8:
		return int(number)
	case uint16:
		return int(number)
	case uint32:
		return int(number)
	case uint64:
		return int(number)
	default:
		return -1
	}
}

func byteFrames(value any) [][]byte {
	if frame, ok := value.([]byte); ok {
		return [][]byte{frame}
	}
	values, ok := value.([]any)
	if !ok {
		return nil
	}
	result := make([][]byte, 0, len(values))
	for _, value := range values {
		if frame, ok := value.([]byte); ok {
			result = append(result, frame)
		}
	}
	return result
}
