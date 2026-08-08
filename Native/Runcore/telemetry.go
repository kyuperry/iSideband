package runcore

import (
	"encoding/binary"
	"math"
	"time"

	"github.com/svanichkin/go-lxmf/lxmf"
	umsgpack "github.com/svanichkin/go-reticulum/rns/vendor"
)

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
