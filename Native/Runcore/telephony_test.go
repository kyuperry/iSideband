package runcore

import (
	"bytes"
	"testing"

	umsgpack "github.com/svanichkin/go-reticulum/rns/vendor"
)

func TestLXSTSignallingEncodingMatchesWireShape(t *testing.T) {
	packed, err := umsgpack.Packb(map[any]any{lxstFieldSignalling: []any{LXSTStatusRinging}})
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[any]any
	if err := umsgpack.Unpackb(packed, &decoded); err != nil {
		t.Fatal(err)
	}
	value, ok := mapIntegerValue(decoded, lxstFieldSignalling)
	if !ok {
		t.Fatal("missing LXST signalling field")
	}
	signals := integerList(value)
	if len(signals) != 1 || signals[0] != LXSTStatusRinging {
		t.Fatalf("unexpected signals: %#v", signals)
	}
}

func TestLXSTFrameEncodingPreservesCodecAndPayload(t *testing.T) {
	wireFrame := append([]byte{LXSTCodecOpus}, []byte{1, 2, 3, 4}...)
	packed, err := umsgpack.Packb(map[any]any{lxstFieldFrames: wireFrame})
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[any]any
	if err := umsgpack.Unpackb(packed, &decoded); err != nil {
		t.Fatal(err)
	}
	value, ok := mapIntegerValue(decoded, lxstFieldFrames)
	if !ok {
		t.Fatal("missing LXST frame field")
	}
	frames := byteFrames(value)
	if len(frames) != 1 || !bytes.Equal(frames[0], wireFrame) {
		t.Fatalf("unexpected frames: %#v", frames)
	}
}

func TestNormalizedLXSTProfileFallsBackToSidebandDefault(t *testing.T) {
	if got := normalizedLXSTProfile(0x99); got != LXSTProfileQualityMedium {
		t.Fatalf("got profile %#x, want %#x", got, LXSTProfileQualityMedium)
	}
}
