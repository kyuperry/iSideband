package runcore

import (
	"encoding/binary"
	"math"
	"time"

	"github.com/svanichkin/go-lxmf/lxmf"
	umsgpack "github.com/svanichkin/go-reticulum/rns/vendor"
)

type ReceivedLocation struct {
	Latitude  float64
	Longitude float64
	Accuracy  float64
	Timestamp int64
}

// LocationTelemetryFields returns Sideband-compatible time and location
// telemetry. It deliberately contains no battery sensor.
func (n *Node) LocationTelemetryFields() map[any]any {
	if n == nil {
		return nil
	}
	n.locationMu.RLock()
	location := n.location
	if location != nil {
		copy := *location
		location = &copy
	}
	n.locationMu.RUnlock()
	if location == nil || time.Now().Unix()-location.Timestamp > 300 {
		return nil
	}

	int32Bytes := func(value int32) []byte {
		data := make([]byte, 4)
		binary.BigEndian.PutUint32(data, uint32(value))
		return data
	}
	uint32Bytes := func(value uint32) []byte {
		data := make([]byte, 4)
		binary.BigEndian.PutUint32(data, value)
		return data
	}
	uint16Bytes := func(value uint16) []byte {
		data := make([]byte, 2)
		binary.BigEndian.PutUint16(data, value)
		return data
	}

	accuracy := math.Max(0, math.Min(location.Accuracy, 655.35))
	packed, err := umsgpack.Packb(map[any]any{
		int64(0x01): location.Timestamp,
		int64(0x02): []any{
			int32Bytes(int32(math.Round(location.Latitude * 1e6))),
			int32Bytes(int32(math.Round(location.Longitude * 1e6))),
			int32Bytes(0), uint32Bytes(0), int32Bytes(0),
			uint16Bytes(uint16(math.Round(accuracy * 100))),
			location.Timestamp,
		},
	})
	if err != nil {
		return nil
	}
	return map[any]any{lxmf.FieldTelemetry: packed}
}

// DecodeLocationTelemetry extracts Sideband-compatible location telemetry
// from an inbound LXMF message field set.
func DecodeLocationTelemetry(fields map[any]any) (ReceivedLocation, bool) {
	var packed []byte
	for key, value := range fields {
		if numericKey(key) != int64(lxmf.FieldTelemetry) {
			continue
		}
		packed, _ = value.([]byte)
		break
	}
	if len(packed) == 0 {
		return ReceivedLocation{}, false
	}

	var sensors map[any]any
	if err := umsgpack.Unpackb(packed, &sensors); err != nil {
		return ReceivedLocation{}, false
	}
	var rawLocation any
	for key, value := range sensors {
		if numericKey(key) == 0x02 {
			rawLocation = value
			break
		}
	}
	values, ok := rawLocation.([]any)
	if !ok || len(values) < 2 {
		return ReceivedLocation{}, false
	}

	latitudeRaw, ok := signedBigEndian(values[0], 4)
	if !ok {
		return ReceivedLocation{}, false
	}
	longitudeRaw, ok := signedBigEndian(values[1], 4)
	if !ok {
		return ReceivedLocation{}, false
	}
	latitude := float64(latitudeRaw) / 1e6
	longitude := float64(longitudeRaw) / 1e6
	if latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 {
		return ReceivedLocation{}, false
	}

	accuracy := 0.0
	if len(values) > 5 {
		if raw, ok := unsignedBigEndian(values[5], 2); ok {
			accuracy = float64(raw) / 100
		}
	}
	timestamp := int64(0)
	if len(values) > 6 {
		timestamp = numericKey(values[6])
	}

	return ReceivedLocation{
		Latitude: latitude, Longitude: longitude,
		Accuracy: accuracy, Timestamp: timestamp,
	}, true
}

func numericKey(value any) int64 {
	switch typed := value.(type) {
	case int:
		return int64(typed)
	case int8:
		return int64(typed)
	case int16:
		return int64(typed)
	case int32:
		return int64(typed)
	case int64:
		return typed
	case uint:
		return int64(typed)
	case uint8:
		return int64(typed)
	case uint16:
		return int64(typed)
	case uint32:
		return int64(typed)
	case uint64:
		if typed <= math.MaxInt64 {
			return int64(typed)
		}
	}
	return -1
}

func signedBigEndian(value any, length int) (int32, bool) {
	data, ok := value.([]byte)
	if !ok || len(data) != length || length != 4 {
		return 0, false
	}
	return int32(binary.BigEndian.Uint32(data)), true
}

func unsignedBigEndian(value any, length int) (uint64, bool) {
	data, ok := value.([]byte)
	if !ok || len(data) != length {
		return 0, false
	}
	switch length {
	case 2:
		return uint64(binary.BigEndian.Uint16(data)), true
	case 4:
		return uint64(binary.BigEndian.Uint32(data)), true
	default:
		return 0, false
	}
}
