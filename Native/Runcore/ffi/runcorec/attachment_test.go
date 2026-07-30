package main

import (
	"os"
	"testing"

	"github.com/svanichkin/go-lxmf/lxmf"
)

func TestInboundAttachmentDecodesSidebandImageField(t *testing.T) {
	message := &lxmf.LXMessage{
		MessageID: []byte{0x01, 0x02},
		Fields: map[any]any{
			lxmf.FieldImage: []any{"webp", []byte{1, 2, 3}},
		},
	}

	path, name, mimeName, attachmentType :=
		inboundAttachment(message)
	t.Cleanup(func() { _ = os.Remove(path) })

	if path == "" {
		t.Fatal("image field was not persisted")
	}
	if name != "photo.webp" {
		t.Fatalf("name=%q want photo.webp", name)
	}
	if mimeName != "image/webp" {
		t.Fatalf("mime=%q want image/webp", mimeName)
	}
	if attachmentType != 1 {
		t.Fatalf("attachment type=%d want photo", attachmentType)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read persisted image: %v", err)
	}
	if len(data) != 3 {
		t.Fatalf("persisted image length=%d want 3", len(data))
	}
}

func TestAttachmentStringAcceptsMsgpackBinaryFormat(t *testing.T) {
	if got := attachmentString([]byte("jpg")); got != "jpg" {
		t.Fatalf("format=%q want jpg", got)
	}
}

func TestInboundAttachmentAcceptsCompactNumericFieldKey(t *testing.T) {
	message := &lxmf.LXMessage{
		MessageID: []byte{0x03, 0x04},
		Fields: map[any]any{
			int8(lxmf.FieldImage): []any{
				[]byte("webp"),
				[]byte{4, 5, 6},
			},
		},
	}

	path, _, _, attachmentType := inboundAttachment(message)
	t.Cleanup(func() { _ = os.Remove(path) })

	if path == "" || attachmentType != 1 {
		t.Fatal("compact numeric image field key was not decoded")
	}
}

func TestInboundFileAttachmentAcceptsSidebandStringName(t *testing.T) {
	message := &lxmf.LXMessage{
		MessageID: []byte{0x05, 0x06},
		Fields: map[any]any{
			int8(lxmf.FieldFileAttachments): []any{
				[]any{"notes.txt", []byte("hello")},
			},
		},
	}

	path, name, mimeName, attachmentType := inboundAttachment(message)
	if path == "" {
		t.Fatal("Sideband string-named file was not persisted")
	}
	t.Cleanup(func() { _ = os.Remove(path) })
	if name != "notes.txt" {
		t.Fatalf("name=%q want notes.txt", name)
	}
	if mimeName != "text/plain; charset=utf-8" &&
		mimeName != "text/plain" {
		t.Fatalf("mime=%q want text/plain", mimeName)
	}
	if attachmentType != 2 {
		t.Fatalf("attachment type=%d want file", attachmentType)
	}
}
