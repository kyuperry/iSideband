package runcore

import (
	"encoding/binary"
	"math"
	"testing"
	"time"

	"github.com/svanichkin/go-lxmf/lxmf"
	umsgpack "github.com/svanichkin/go-reticulum/rns/vendor"
)

func TestDecodeLocationTelemetry(t *testing.T) {
	int32Bytes := func(value int32) []byte {
		data := make([]byte, 4)
		binary.BigEndian.PutUint32(data, uint32(value))
		return data
	}
	accuracy := []byte{0x04, 0xD2}
	packed, err := umsgpack.Packb(map[any]any{
		int64(0x01): int64(1_700_000_000),
		int64(0x02): []any{
			int32Bytes(20_798_400),
			int32Bytes(-156_331_900),
			int32Bytes(0), []byte{0, 0, 0, 0}, int32Bytes(0),
			accuracy, int64(1_700_000_000),
		},
	})
	if err != nil {
		t.Fatal(err)
	}

	location, ok := DecodeLocationTelemetry(map[any]any{
		int64(lxmf.FieldTelemetry): packed,
	})
	if !ok {
		t.Fatal("expected location telemetry")
	}
	if math.Abs(location.Latitude-20.7984) > 0.000001 ||
		math.Abs(location.Longitude-(-156.3319)) > 0.000001 {
		t.Fatalf("unexpected coordinate: %+v", location)
	}
	if location.Accuracy != 12.34 || location.Timestamp != 1_700_000_000 {
		t.Fatalf("unexpected metadata: %+v", location)
	}
}

func TestDecodeLocationTelemetryRejectsInvalidCoordinate(t *testing.T) {
	data := make([]byte, 4)
	binary.BigEndian.PutUint32(data, uint32(91_000_000))
	zero := []byte{0, 0, 0, 0}
	packed, err := umsgpack.Packb(map[any]any{
		int64(0x02): []any{data, zero},
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := DecodeLocationTelemetry(map[any]any{
		int64(lxmf.FieldTelemetry): packed,
	}); ok {
		t.Fatal("expected invalid coordinate to be rejected")
	}
}

func TestLocationTelemetryFieldsHonorsSensorToggles(t *testing.T) {
	n := &Node{telemetryTimeEnabled: true}
	telemetryPayload := func(fields map[any]any) []byte {
		for key, value := range fields {
			if numericKey(key) == int64(lxmf.FieldTelemetry) {
				packed, _ := value.([]byte)
				return packed
			}
		}
		return nil
	}

	fields := n.LocationTelemetryFields()
	packed := telemetryPayload(fields)
	if len(packed) == 0 {
		t.Fatal("expected timestamp telemetry")
	}
	var sensors map[any]any
	if err := umsgpack.Unpackb(packed, &sensors); err != nil {
		t.Fatalf("unpack timestamp telemetry: %v", err)
	}
	if _, ok := sensors[int64(0x01)]; !ok {
		t.Fatal("expected timestamp sensor")
	}
	if _, ok := sensors[int64(0x02)]; ok {
		t.Fatal("did not expect location sensor")
	}

	n.SetTelemetryTimeEnabled(false)
	if fields := n.LocationTelemetryFields(); fields != nil {
		t.Fatal("expected no telemetry with both sensors disabled")
	}

	n.SetAnnounceLocation(20.8, -156.3, 5, time.Now().Unix(), true)
	fields = n.LocationTelemetryFields()
	packed = telemetryPayload(fields)
	if len(packed) == 0 {
		t.Fatal("expected location telemetry")
	}
	sensors = nil
	if err := umsgpack.Unpackb(packed, &sensors); err != nil {
		t.Fatalf("unpack location telemetry: %v", err)
	}
	if _, ok := sensors[int64(0x01)]; ok {
		t.Fatal("did not expect timestamp sensor")
	}
	if _, ok := sensors[int64(0x02)]; !ok {
		t.Fatal("expected location sensor")
	}
}
