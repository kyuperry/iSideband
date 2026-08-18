package main

/*
#include <stdint.h>
 #include <stdlib.h>
typedef void (*runcore_log_cb)(void* user_data, int32_t level, const char* line);
typedef void (*runcore_raw_tx_cb)(void* user_data, const uint8_t* data, int32_t len);
typedef void (*runcore_inbound_cb)(void* user_data, const char* source, const char* title, const char* content, double timestamp, const char* message_id, const char* attachment_path, const char* attachment_name, const char* attachment_mime, int32_t attachment_type, int32_t has_location, double latitude, double longitude, double accuracy, int64_t location_timestamp);
typedef void (*runcore_status_cb)(void* user_data, const char* client_id, const char* status);

static inline void runcore_log_cb_call(runcore_log_cb cb, void* user_data, int32_t level, const char* line) {
  cb(user_data, level, line);
}
static inline void runcore_raw_tx_cb_call(runcore_raw_tx_cb cb, void* user_data, const uint8_t* data, int32_t len) {
  cb(user_data, data, len);
}
static inline void runcore_inbound_cb_call(runcore_inbound_cb cb, void* user_data, const char* source, const char* title, const char* content, double timestamp, const char* message_id, const char* attachment_path, const char* attachment_name, const char* attachment_mime, int32_t attachment_type, int32_t has_location, double latitude, double longitude, double accuracy, int64_t location_timestamp) {
  cb(user_data, source, title, content, timestamp, message_id, attachment_path, attachment_name, attachment_mime, attachment_type, has_location, latitude, longitude, accuracy, location_timestamp);
}
static inline void runcore_status_cb_call(runcore_status_cb cb, void* user_data, const char* client_id, const char* status) {
  cb(user_data, client_id, status);
}
*/
import "C"

import (
	"encoding/hex"
	"fmt"
	"mime"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/svanichkin/go-lxmf/lxmf"
	"github.com/svanichkin/go-reticulum/rns"

	"runcore"
)

type nodeHandle struct {
	node         *runcore.Node
	rawInterface *rns.Interface
	rawTxCB      C.runcore_raw_tx_cb
	rawTxUser    unsafe.Pointer
	inboundCB    C.runcore_inbound_cb
	inboundUser  unsafe.Pointer
	statusCB     C.runcore_status_cb
	statusUser   unsafe.Pointer
}

var (
	nextID  uint64 = 1
	nodes          = map[uint64]*nodeHandle{}
	nodesMu sync.RWMutex

	logMu       sync.RWMutex
	logCB       C.runcore_log_cb
	logUserData unsafe.Pointer
)

func main() {}

func allocCString(s string) *C.char { return C.CString(s) }

//export runcore_free_string
func runcore_free_string(p *C.char) {
	if p == nil {
		return
	}
	C.free(unsafe.Pointer(p))
}

//export runcore_ingest_lxm_uri
func runcore_ingest_lxm_uri(handle C.uint64_t, uri *C.char) C.int32_t {
	if uri == nil {
		return -1
	}
	nodesMu.RLock()
	h := nodes[uint64(handle)]
	nodesMu.RUnlock()
	if h == nil || h.node == nil {
		return -1
	}
	result, err := h.node.IngestLXMURI(C.GoString(uri))
	if err != nil {
		return -1
	}
	return C.int32_t(result)
}

//export runcore_default_lxmd_config
func runcore_default_lxmd_config() *C.char {
	return allocCString(runcore.DefaultLXMDConfigText(""))
}

const defaultRNSConfigLogLevel = 4

//export runcore_default_rns_config
func runcore_default_rns_config() *C.char {
	return allocCString(runcore.DefaultRNSConfigText(defaultRNSConfigLogLevel))
}

//export runcore_start
func runcore_start(contactsDir *C.char, sendDir *C.char, messagesDir *C.char, loglevel C.int32_t) C.uint64_t {
	contacts := ""
	if contactsDir != nil {
		contacts = C.GoString(contactsDir)
	}
	send := ""
	if sendDir != nil {
		send = C.GoString(sendDir)
	}
	messages := ""
	if messagesDir != nil {
		messages = C.GoString(messagesDir)
	}
	level := int(loglevel)
	rootDir := ""
	if contacts != "" {
		rootDir = filepath.Dir(strings.TrimSpace(contacts))
	}

	checkDirReadableWritable(contacts)
	checkDirReadableWritable(send)
	checkDirReadableWritable(messages)
	checkDirReadableWritable(rootDir)

	n, err := runcore.Start(runcore.Options{
		Dir:                     rootDir,
		ContactsDir:             contacts,
		SendDir:                 send,
		MessagesDir:             messages,
		LogLevel:                level,
		DisablePeriodicAnnounce: true,
	})
	if err != nil {
		rns.Log(fmt.Sprintf("runcore_start failed: %v", err), rns.LOG_ERROR)
		return 0
	}

	// The embedded iOS app supplies its own RNode-backed raw interface below.
	// Leaving the generated AutoInterface enabled makes iOS repeatedly attempt
	// local multicast discovery, which is blocked by the platform firewall and
	// can leave sustained Resource traffic associated with an unusable route.
	// Disable only that generated interface; the raw RNode interface is attached
	// separately by runcore_attach_raw_interface().
	if err := n.SetInterfaceEnabled("Default Interface", false); err != nil {
		rns.Logf(rns.LOG_WARNING, "runcore: disable embedded Default Interface: %v", err)
	}

	h := &nodeHandle{node: n}

	nodesMu.Lock()
	id := nextID
	nodes[id] = h
	nodesMu.Unlock()

	return C.uint64_t(id)
}

func checkDirReadableWritable(dir string) {
	dir = strings.TrimSpace(dir)
	if dir == "" {
		return
	}

	p := filepath.Join(dir, ".rwcheck")
	want := []byte("ok")
	if err := os.WriteFile(p, want, 0o644); err != nil {
		return
	}
	got, err := os.ReadFile(p)
	_ = os.Remove(p)
	if err != nil {
		return
	}
	if string(got) != string(want) {
		return
	}
}

func getHandle(id C.uint64_t) *nodeHandle {
	nodesMu.RLock()
	h := nodes[uint64(id)]
	nodesMu.RUnlock()
	return h
}

//export runcore_stop
func runcore_stop(handle C.uint64_t) C.int32_t {
	nodesMu.Lock()
	h := nodes[uint64(handle)]
	delete(nodes, uint64(handle))
	nodesMu.Unlock()
	if h == nil {
		return 0
	}
	if h.rawInterface != nil {
		h.rawInterface.Detach()
	}
	_ = h.node.Close()
	return 0
}

//export runcore_attach_raw_interface
func runcore_attach_raw_interface(handle C.uint64_t, cb C.runcore_raw_tx_cb, userData unsafe.Pointer, bitrate C.int32_t) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil || rns.Owner == nil || cb == nil {
		return 1
	}
	if h.rawInterface != nil {
		return 0
	}
	ifc := &rns.Interface{Name: "iSideband RNode", Type: "iSidebandRaw", IN: true, OUT: true, Online: true, Bitrate: int(bitrate), HWMTU: 500, AutoconfigureMTU: true, DriverImplemented: true}
	ifc.FinalInit()
	h.rawTxCB, h.rawTxUser = cb, userData
	ifc.SetProcessOutgoingFunc(func(data []byte) error {
		if len(data) == 0 {
			return nil
		}
		nodesMu.RLock()
		current := nodes[uint64(handle)]
		nodesMu.RUnlock()
		if current == nil || current.rawTxCB == nil {
			return fmt.Errorf("raw interface callback unavailable")
		}
		C.runcore_raw_tx_cb_call(current.rawTxCB, current.rawTxUser, (*C.uint8_t)(unsafe.Pointer(&data[0])), C.int32_t(len(data)))
		return nil
	})
	rns.Owner.AddInterface(ifc, rns.InterfaceModeFull, nil, nil, nil, nil, nil, nil, nil, nil)
	h.rawInterface = ifc
	return 0
}

//export runcore_raw_interface_receive
func runcore_raw_interface_receive(handle C.uint64_t, data *C.uint8_t, length C.int32_t) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.rawInterface == nil || data == nil || length <= 0 {
		return 1
	}
	rns.Inbound(C.GoBytes(unsafe.Pointer(data), C.int(length)), h.rawInterface)
	return 0
}

//export runcore_announce
func runcore_announce(handle C.uint64_t) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return 1
	}
	h.node.AnnounceDelivery()
	return 0
}

//export runcore_set_announce_location
func runcore_set_announce_location(handle C.uint64_t, latitude C.double, longitude C.double, accuracy C.double, timestamp C.int64_t, enabled C.int32_t) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return 1
	}
	h.node.SetAnnounceLocation(float64(latitude), float64(longitude), float64(accuracy), int64(timestamp), enabled != 0)
	return 0
}

//export runcore_send_text
func runcore_send_text(handle C.uint64_t, destination *C.char, content *C.char, direct C.int32_t, clientID *C.char) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil || destination == nil || content == nil || clientID == nil {
		return 1
	}
	id := C.GoString(clientID)
	notifyStatus(h, id, "sending")
	method := byte(lxmf.MethodOpportunistic)
	if direct != 0 {
		method = lxmf.MethodDirect
	}
	fields := h.node.LocationTelemetryFields()
	msg, err := h.node.SendHex(C.GoString(destination), runcore.SendOptions{Method: method, Content: C.GoString(content), Fields: fields})
	if err != nil {
		rns.Log(fmt.Sprintf("runcore_send_text failed: %v", err), rns.LOG_ERROR)
		notifyStatus(h, id, "failed")
		return 2
	}
	var terminalStatus sync.Once
	msg.RegisterDeliveryCallback(func(*lxmf.LXMessage) {
		terminalStatus.Do(func() {
			notifyStatus(h, id, "delivered")
		})
	})
	msg.RegisterFailedCallback(func(*lxmf.LXMessage) {
		terminalStatus.Do(func() {
			notifyStatus(h, id, "failed")
		})
	})
	notifyStatus(h, id, "sent")
	return 0
}

func notifyStatus(h *nodeHandle, clientID, status string) {
	if h == nil || h.statusCB == nil || strings.TrimSpace(clientID) == "" {
		return
	}
	cid, state := C.CString(clientID), C.CString(status)
	C.runcore_status_cb_call(h.statusCB, h.statusUser, cid, state)
	C.free(unsafe.Pointer(cid))
	C.free(unsafe.Pointer(state))
}

//export runcore_set_status_cb
func runcore_set_status_cb(handle C.uint64_t, cb C.runcore_status_cb, userData unsafe.Pointer) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil || cb == nil {
		return 1
	}
	h.statusCB, h.statusUser = cb, userData
	return 0
}

//export runcore_send_attachment
func runcore_send_attachment(handle C.uint64_t, destination *C.char, content *C.char, filePath *C.char, fileName *C.char, mimeType *C.char, clientID *C.char) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil || destination == nil || filePath == nil || clientID == nil {
		return 1
	}
	path := C.GoString(filePath)
	data, err := os.ReadFile(path)
	if err != nil || len(data) == 0 {
		return 2
	}
	name := filepath.Base(path)
	if fileName != nil && strings.TrimSpace(C.GoString(fileName)) != "" {
		name = filepath.Base(C.GoString(fileName))
	}
	mimeName := ""
	if mimeType != nil {
		mimeName = strings.ToLower(strings.TrimSpace(C.GoString(mimeType)))
	}
	fields := map[any]any{}
	for key, value := range h.node.LocationTelemetryFields() {
		fields[key] = value
	}
	if mimeName == "audio/ogg" || mimeName == "audio/opus" {
		// Sideband renders and plays voice messages only when they use the
		// standard LXMF audio field [AM_OPUS_OGG, oggBytes].
		fields[lxmf.FieldAudio] = []any{lxmf.AMOpusOgg, data}
	} else if strings.HasPrefix(mimeName, "image/") {
		format := strings.TrimPrefix(mimeName, "image/")
		if format == "" {
			format = strings.TrimPrefix(
				strings.ToLower(filepath.Ext(name)),
				".",
			)
		}
		if format == "jpeg" {
			format = "jpg"
		}
		if format == "" {
			format = "jpg"
		}
		// Sideband and other LXMF clients encode photos as [format, bytes].
		fields[lxmf.FieldImage] = []any{format, data}
	} else {
		fields[lxmf.FieldFileAttachments] =
			[]any{[]any{name, data}}
	}
	text := ""
	if content != nil {
		text = C.GoString(content)
	}
	id := C.GoString(clientID)
	destinationHex := C.GoString(destination)
	notifyStatus(h, id, "sending")

	// Route discovery is asynchronous. Keep the attachment job alive while a
	// fresh announce/path is acquired instead of making the Swift caller wait or
	// reporting the message as sent before LXMF has delivered it.
	go func() {
		if destinationHash, decodeErr := hex.DecodeString(destinationHex); decodeErr == nil &&
			len(destinationHash) == lxmf.DestinationLength &&
			!rns.TransportHasPath(destinationHash) {
			rns.Logf(rns.LOG_NOTICE, "ATTACHMENT WAITING FOR PATH destination=%s", destinationHex)
			rns.TransportRequestPath(destinationHash)
			deadline := time.Now().Add(12 * time.Second)
			for !rns.TransportHasPath(destinationHash) && time.Now().Before(deadline) {
				time.Sleep(150 * time.Millisecond)
			}
			if rns.TransportHasPath(destinationHash) {
				rns.Logf(rns.LOG_NOTICE, "ATTACHMENT PATH ACQUIRED destination=%s", destinationHex)
			} else {
				rns.Logf(rns.LOG_NOTICE, "ATTACHMENT PATH STILL PENDING destination=%s; retaining LXMF job", destinationHex)
			}
		}

		msg, sendErr := h.node.SendHex(destinationHex, runcore.SendOptions{Method: lxmf.MethodDirect, Content: text, Fields: fields})
		if sendErr != nil {
			rns.Logf(rns.LOG_ERROR, "runcore_send_attachment failed: %v", sendErr)
			notifyStatus(h, id, "failed")
			return
		}
		var terminalStatus sync.Once
		msg.RegisterDeliveryCallback(func(*lxmf.LXMessage) {
			terminalStatus.Do(func() {
				notifyStatus(h, id, "delivered")
			})
		})
		msg.RegisterFailedCallback(func(m *lxmf.LXMessage) {
			rns.Logf(
				rns.LOG_ERROR,
				"LXMF FAILED: state=%d progress=%.2f representation=%d method=%d attempts=%d",
				m.State,
				m.Progress,
				m.Representation,
				m.Method,
				m.DeliveryAttempts,
			)

			terminalStatus.Do(func() {
				notifyStatus(h, id, "failed")
			})
		})
	}()
	return 0
}

func messageIDHex(m *lxmf.LXMessage) string {
	if m == nil {
		return ""
	}
	if len(m.MessageID) > 0 {
		return hex.EncodeToString(m.MessageID)
	}
	return hex.EncodeToString(m.Hash)
}

func inboundAttachment(m *lxmf.LXMessage) (path, name, mimeName string, attachmentType int32) {
	if m == nil {
		return
	}
	if value, ok := lxmfFieldValue(m.Fields, lxmf.FieldImage); ok {
		pair, ok := value.([]any)
		if !ok || len(pair) < 2 {
			return
		}
		format := attachmentString(pair[0])
		data, ok := pair[1].([]byte)
		if !ok || len(data) == 0 {
			return "", "", "", 0
		}
		format = strings.ToLower(
			strings.TrimPrefix(strings.TrimSpace(format), "."),
		)
		if format == "jpeg" {
			format = "jpg"
		}
		if format == "" {
			format = "jpg"
		}
		name = "photo." + format
		mimeName = "image/" + format
		path = persistInboundAttachment(m, name, data)
		if path == "" {
			return "", "", "", 0
		}
		return path, name, mimeName, 1
	}

	if value, ok := lxmfFieldValue(m.Fields, lxmf.FieldAudio); ok {
		pair, pairOK := value.([]any)
		if !pairOK || len(pair) < 2 {
			return
		}
		mode := numericFieldKey(pair[0])
		data, dataOK := pair[1].([]byte)
		if !dataOK || len(data) == 0 {
			return
		}
		if mode == lxmf.AMOpusOgg {
			name = "voice.ogg"
			mimeName = "audio/ogg"
		} else if mode >= lxmf.AMCodec2700C && mode <= lxmf.AMCodec23200 {
			// Preserve Sideband's low-bandwidth Codec2 payload and identify it as
			// voice instead of silently producing an empty text message.
			name = fmt.Sprintf("voice-codec2-%02x.c2", mode)
			mimeName = fmt.Sprintf("audio/x-codec2; mode=%d", mode)
		} else {
			name = fmt.Sprintf("voice-mode-%02x.bin", mode)
			mimeName = fmt.Sprintf("audio/x-lxmf; mode=%d", mode)
		}
		path = persistInboundAttachment(m, name, data)
		if path == "" {
			return "", "", "", 0
		}
		return path, name, mimeName, 3
	}

	value, ok := lxmfFieldValue(
		m.Fields,
		lxmf.FieldFileAttachments,
	)
	if !ok {
		return
	}
	items, ok := value.([]any)
	if !ok || len(items) == 0 {
		return
	}
	pair, ok := items[0].([]any)
	if !ok || len(pair) < 2 {
		return
	}
	nameValue := attachmentString(pair[0])
	data, ok := pair[1].([]byte)
	if nameValue == "" || !ok || len(data) == 0 {
		return
	}
	name = filepath.Base(nameValue)
	if name == "." || name == "" {
		name = "attachment.bin"
	}
	mimeName = mime.TypeByExtension(filepath.Ext(name))
	if mimeName == "" {
		mimeName = "application/octet-stream"
	}
	path = persistInboundAttachment(m, name, data)
	if path == "" {
		return "", "", "", 0
	}
	if strings.HasPrefix(mimeName, "image/") {
		attachmentType = 1
	} else {
		attachmentType = 2
	}
	return
}

func lxmfFieldValue(
	fields map[any]any,
	wanted int,
) (any, bool) {
	for key, value := range fields {
		if numericFieldKey(key) == wanted {
			return value, true
		}
	}
	return nil, false
}

func numericFieldKey(value any) int {
	switch typed := value.(type) {
	case int:
		return typed
	case int8:
		return int(typed)
	case int16:
		return int(typed)
	case int32:
		return int(typed)
	case int64:
		return int(typed)
	case uint:
		return int(typed)
	case uint8:
		return int(typed)
	case uint16:
		return int(typed)
	case uint32:
		return int(typed)
	case uint64:
		if typed <= uint64(^uint(0)>>1) {
			return int(typed)
		}
	}
	return -1
}

func attachmentString(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case []byte:
		return string(typed)
	default:
		return ""
	}
}

func persistInboundAttachment(
	m *lxmf.LXMessage,
	name string,
	data []byte,
) string {
	dir := filepath.Join(os.TempDir(), "iSidebandIncomingAttachments")
	if os.MkdirAll(dir, 0o755) != nil {
		return ""
	}
	path := filepath.Join(dir, messageIDHex(m)+"-"+filepath.Base(name))
	if os.WriteFile(path, data, 0o600) != nil {
		return ""
	}
	return path
}

//export runcore_set_inbound_cb
func runcore_set_inbound_cb(handle C.uint64_t, cb C.runcore_inbound_cb, userData unsafe.Pointer) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil || cb == nil {
		return 1
	}
	h.inboundCB, h.inboundUser = cb, userData
	h.node.SetInboundHandler(func(m *lxmf.LXMessage) {
		if m == nil {
			return
		}
		source := C.CString(fmt.Sprintf("%x", m.SourceHash))
		title := C.CString(m.TitleAsString())
		content := C.CString(m.ContentAsString())
		messageID := C.CString(messageIDHex(m))
		pathValue, nameValue, mimeValue, attachmentType := inboundAttachment(m)
		path := C.CString(pathValue)
		name := C.CString(nameValue)
		mimeName := C.CString(mimeValue)
		location, hasLocation := runcore.DecodeLocationTelemetry(m.Fields)
		locationFlag := C.int32_t(0)
		if hasLocation {
			locationFlag = 1
		}
		C.runcore_inbound_cb_call(h.inboundCB, h.inboundUser, source, title, content, C.double(m.Timestamp), messageID, path, name, mimeName, C.int32_t(attachmentType), locationFlag, C.double(location.Latitude), C.double(location.Longitude), C.double(location.Accuracy), C.int64_t(location.Timestamp))
		C.free(unsafe.Pointer(source))
		C.free(unsafe.Pointer(title))
		C.free(unsafe.Pointer(content))
		C.free(unsafe.Pointer(messageID))
		C.free(unsafe.Pointer(path))
		C.free(unsafe.Pointer(name))
		C.free(unsafe.Pointer(mimeName))
	})
	return 0
}

//export runcore_set_log_cb
func runcore_set_log_cb(cb C.runcore_log_cb, userData unsafe.Pointer) {
	logMu.Lock()
	logCB = cb
	logUserData = userData
	logMu.Unlock()

	if cb == nil {
		rns.SetLogDestCallback(nil)
		return
	}
	rns.SetLogDestCallback(func(level int, msg string) {
		logMu.RLock()
		c := logCB
		ud := logUserData
		logMu.RUnlock()
		if c == nil {
			return
		}
		cLine := allocCString(msg)
		C.runcore_log_cb_call(c, ud, C.int32_t(level), cLine)
		C.free(unsafe.Pointer(cLine))
	})

	// Emit a marker so clients can verify the hook works without waiting for network activity.
	rns.Log("runcore: log callback enabled", rns.LOG_NOTICE)
}

//export runcore_set_loglevel
func runcore_set_loglevel(level C.int32_t) {
	rns.SetLogLevel(int(level))
}

//export runcore_config_dir
func runcore_config_dir(handle C.uint64_t) *C.char {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return nil
	}
	return allocCString(h.node.ConfigDir())
}

//export runcore_destination_hash_hex
func runcore_destination_hash_hex(handle C.uint64_t) *C.char {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return nil
	}
	return allocCString(h.node.DestinationHashHex())
}

//export runcore_set_display_name
func runcore_set_display_name(handle C.uint64_t, displayName *C.char) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return 1
	}
	name := ""
	if displayName != nil {
		name = C.GoString(displayName)
	}
	if err := h.node.SetDisplayName(name); err != nil {
		return 2
	}
	return 0
}

//export runcore_restart
func runcore_restart(handle C.uint64_t) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return 1
	}
	if err := h.node.Restart(); err != nil {
		return 2
	}
	return 0
}

//export runcore_reset_profile
func runcore_reset_profile(handle C.uint64_t) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return 1
	}
	if err := h.node.ResetProfile(); err != nil {
		return 2
	}
	return 0
}

//export runcore_interface_stats_json
func runcore_interface_stats_json(handle C.uint64_t) *C.char {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return nil
	}
	return allocCString(h.node.InterfaceStatsJSON())
}

//export runcore_set_interface_enabled
func runcore_set_interface_enabled(handle C.uint64_t, name *C.char, enabled C.int32_t) C.int32_t {
	h := getHandle(handle)
	if h == nil || h.node == nil {
		return 1
	}
	if name == nil {
		return 2
	}
	if err := h.node.SetInterfaceEnabled(C.GoString(name), enabled != 0); err != nil {
		return 3
	}
	return 0
}
