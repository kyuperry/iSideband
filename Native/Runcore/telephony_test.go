package runcore

import (
	"bytes"
	"testing"

	"github.com/svanichkin/go-reticulum/rns"
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

func TestSameLXSTLinkMatchesEquivalentLinkIDs(t *testing.T) {
	first := &rns.Link{LinkID: []byte{1, 2, 3, 4}}
	second := &rns.Link{LinkID: []byte{1, 2, 3, 4}}
	different := &rns.Link{LinkID: []byte{4, 3, 2, 1}}

	if !sameLXSTLink(first, second) {
		t.Fatal("equivalent Reticulum link IDs should match")
	}
	if sameLXSTLink(first, different) {
		t.Fatal("different Reticulum link IDs should not match")
	}
}
