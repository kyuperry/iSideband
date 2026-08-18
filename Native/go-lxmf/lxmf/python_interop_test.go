package lxmf

import (
	"encoding/hex"
	"encoding/json"
	"os"
	"testing"

	"github.com/svanichkin/go-reticulum/rns"
)

type pythonLXMFVector struct {
	DestinationHash string `json:"destination_hash"`
	SourceHash      string `json:"source_hash"`
	Title           string `json:"title"`
	Content         string `json:"content"`
	PackedHex       string `json:"packed_hex"`
}

// This fixture is produced by the canonical Python RNS/LXMF packages from
// fixed identities and a fixed timestamp. It prevents the native iOS core from
// silently drifting away from the wire format used by Android Sideband.
func TestCanonicalPythonDirectMessageVector(t *testing.T) {
	fixtureBytes, err := os.ReadFile("testdata/python_lxmf_direct.json")
	if err != nil {
		t.Fatalf("read canonical vector: %v", err)
	}
	var vector pythonLXMFVector
	if err := json.Unmarshal(fixtureBytes, &vector); err != nil {
		t.Fatalf("decode canonical vector: %v", err)
	}

	sourcePrivate := make([]byte, 64)
	for i := range sourcePrivate {
		sourcePrivate[i] = byte(i)
	}
	sourceIdentity, err := rns.NewIdentity()
	if err != nil {
		t.Fatalf("create source identity: %v", err)
	}
	if err := sourceIdentity.LoadPrivateKey(sourcePrivate); err != nil {
		t.Fatalf("load canonical source identity: %v", err)
	}
	sourceHash, err := hex.DecodeString(vector.SourceHash)
	if err != nil {
		t.Fatalf("decode source hash: %v", err)
	}
	if err := rns.IdentityRemember(
		make([]byte, rns.ReticulumTruncatedHashLength/8),
		sourceHash,
		sourceIdentity.GetPublicKey(),
		nil,
	); err != nil {
		t.Fatalf("remember canonical source identity: %v", err)
	}

	packed, err := hex.DecodeString(vector.PackedHex)
	if err != nil {
		t.Fatalf("decode packed message: %v", err)
	}
	message, err := UnpackFromBytes(packed, MethodDirect)
	if err != nil {
		t.Fatalf("unpack Python LXMF message: %v", err)
	}
	if got := hex.EncodeToString(message.DestinationHash); got != vector.DestinationHash {
		t.Fatalf("destination hash mismatch: got %s", got)
	}
	if got := hex.EncodeToString(message.SourceHash); got != vector.SourceHash {
		t.Fatalf("source hash mismatch: got %s", got)
	}
	if got := message.TitleAsString(); got != vector.Title {
		t.Fatalf("title mismatch: got %q", got)
	}
	if got := message.ContentAsString(); got != vector.Content {
		t.Fatalf("content mismatch: got %q", got)
	}
	if !message.SignatureValidated {
		t.Fatal("canonical Python LXMF signature did not validate")
	}
	customType, ok := message.Fields[int64(FieldCustomType)]
	if !ok {
		customType = message.Fields[uint64(FieldCustomType)]
	}
	if customType != "isideband.interop" {
		t.Fatalf("custom field mismatch: %#v in %#v", customType, message.Fields)
	}
}

func TestUnpackRejectsTruncatedCanonicalMessages(t *testing.T) {
	fixtureBytes, err := os.ReadFile("testdata/python_lxmf_direct.json")
	if err != nil {
		t.Fatalf("read canonical vector: %v", err)
	}
	var vector pythonLXMFVector
	if err := json.Unmarshal(fixtureBytes, &vector); err != nil {
		t.Fatalf("decode canonical vector: %v", err)
	}
	packed, err := hex.DecodeString(vector.PackedHex)
	if err != nil {
		t.Fatalf("decode packed message: %v", err)
	}

	for _, length := range []int{0, 1, DestinationLength, len(packed) / 2} {
		func() {
			defer func() {
				if recovered := recover(); recovered != nil {
					t.Fatalf("length %d caused panic: %v", length, recovered)
				}
			}()
			if _, err := UnpackFromBytes(packed[:length], MethodDirect); err == nil {
				t.Fatalf("length %d unexpectedly decoded", length)
			}
		}()
	}
}
