package runcore

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/svanichkin/go-lxmf/lxmf"
	"github.com/svanichkin/go-reticulum/rns"
)

const messagesFromXattr = "user.from"
const messageDateXattr = "user.date"
const messageStatusXattr = "user.status"
const messageToXattr = "user.to"
const messageStatusUnseen = "unseen"

// persistInboundMessage stores inbound LXMF messages on disk in a deterministic, app-friendly layout:
//
//	messagesDir/<srcHashHex>/YYYY-MM-DD HH꞉MM.txt                      (plain text)
//	messagesDir/<srcHashHex>/YYYY-MM-DD HH꞉MM <filename>.<ext>         (attachment-like)
func (n *Node) persistInboundMessage(m *lxmf.LXMessage) {
	if n == nil || m == nil {
		return
	}
	root := strings.TrimSpace(n.messagesDir)
	if root == "" {
		return
	}
	if err := os.MkdirAll(root, 0o755); err != nil {
		rns.Logf(rns.LOG_WARNING, "runcore: create messages dir: %v", err)
		return
	}

	src := strings.ToLower(strings.TrimSpace(fmt.Sprintf("%x", m.SourceHash)))
	if src == "" {
		src = "unknown"
	}
	dir := filepath.Join(root, src)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		rns.Logf(rns.LOG_WARNING, "runcore: create messages src dir: %v", err)
		return
	}
	// Ensure the thread folder has the sender id so UI can associate the directory.
	n.ensureMessagesDirFromTag(dir, src)

	ts := messageTime(m)
	prefix := formatMessageMinute(ts)
	tsUnix := ts.Unix()
	to := strings.ToLower(strings.TrimSpace(n.DestinationHashHex()))
	// Android Sideband attachment support
	// Android Sideband native LXMF file attachment support.

	// Android Sideband native LXMF image support.
	if m.Fields != nil {
		if value, ok := m.Fields[lxmf.FieldImage]; ok {
			imageField, ok := value.([]any)
			if !ok || len(imageField) < 2 {
				rns.Logf(
					rns.LOG_WARNING,
					"runcore: malformed image field type=%T",
					value,
				)
			} else {
				var imageExtension string
				switch value := imageField[0].(type) {
				case string:
					imageExtension = value
				case []byte:
					imageExtension = string(value)
				}

				imageExtension = strings.TrimPrefix(
					strings.ToLower(
						strings.TrimSpace(imageExtension),
					),
					".",
				)

				if imageExtension == "" {
					imageExtension = "jpg"
				}

				imageData, ok := imageField[1].([]byte)
				if !ok || len(imageData) == 0 {
					rns.Logf(
						rns.LOG_WARNING,
						"runcore: unsupported image data type %T",
						imageField[1],
					)
				} else {
					imageName :=
						"image." + imageExtension

					imagePath := uniquePath(
						filepath.Join(
							dir,
							prefix+" "+imageName,
						),
					)

					if err := os.WriteFile(
						imagePath,
						imageData,
						0o644,
					); err != nil {
						rns.Logf(
							rns.LOG_WARNING,
							"runcore: save Sideband image: %v",
							err,
						)
					} else {
						n.setInboundMessageFileTags(
							imagePath,
							tsUnix,
							src,
							to,
						)

						rns.Logf(
							rns.LOG_NOTICE,
							"runcore: saved Sideband image name=%s size=%d",
							imageName,
							len(imageData),
						)

						imageCaption :=
							strings.TrimSpace(
								m.ContentAsString(),
							)

						if imageCaption != "" {
							captionPath := uniquePath(
								filepath.Join(
									dir,
									prefix+".txt",
								),
							)

							if err := os.WriteFile(
								captionPath,
								[]byte(imageCaption),
								0o644,
							); err == nil {
								n.setInboundMessageFileTags(
									captionPath,
									tsUnix,
									src,
									to,
								)
							}
						}

						return
					}
				}
			}
		}
	}
	if m.Fields != nil {
		if value, ok := m.Fields[lxmf.FieldFileAttachments]; ok {
			attachments, ok := value.([]any)
			if !ok {
				rns.Logf(
					rns.LOG_WARNING,
					"runcore: unexpected file attachment field type %T",
					value,
				)
			} else {
				savedAttachment := false

				for _, rawAttachment := range attachments {
					attachment, ok := rawAttachment.([]any)
					if !ok || len(attachment) < 2 {
						rns.Logf(
							rns.LOG_WARNING,
							"runcore: malformed file attachment type=%T",
							rawAttachment,
						)
						continue
					}

					var attachmentName string
					switch value := attachment[0].(type) {
					case string:
						attachmentName = value
					case []byte:
						attachmentName = string(value)
					default:
						rns.Logf(
							rns.LOG_WARNING,
							"runcore: unsupported attachment name type %T",
							attachment[0],
						)
						continue
					}

					attachmentData, ok := attachment[1].([]byte)
					if !ok || len(attachmentData) == 0 {
						rns.Logf(
							rns.LOG_WARNING,
							"runcore: unsupported attachment data type %T",
							attachment[1],
						)
						continue
					}

					attachmentName =
						sanitizeMessageName(attachmentName)

					if attachmentName == "" {
						attachmentName = "attachment.bin"
					}

					attachmentPath := uniquePath(
						filepath.Join(
							dir,
							prefix+" "+attachmentName,
						),
					)

					if err := os.WriteFile(
						attachmentPath,
						attachmentData,
						0o644,
					); err != nil {
						rns.Logf(
							rns.LOG_WARNING,
							"runcore: save Sideband attachment: %v",
							err,
						)
						continue
					}

					n.setInboundMessageFileTags(
						attachmentPath,
						tsUnix,
						src,
						to,
					)

					savedAttachment = true

					rns.Logf(
						rns.LOG_NOTICE,
						"runcore: saved Sideband attachment name=%s size=%d",
						attachmentName,
						len(attachmentData),
					)
				}

				if savedAttachment {
					attachmentCaption :=
						strings.TrimSpace(
							m.ContentAsString(),
						)

					if attachmentCaption != "" {
						captionPath := uniquePath(
							filepath.Join(
								dir,
								prefix+".txt",
							),
						)

						if err := os.WriteFile(
							captionPath,
							[]byte(attachmentCaption),
							0o644,
						); err == nil {
							n.setInboundMessageFileTags(
								captionPath,
								tsUnix,
								src,
								to,
							)
						}
					}

					return
				}
			}
		}
	}
	title := strings.TrimSpace(m.TitleAsString())
	content := m.ContentAsString()

	name := ""
	ext := ""
	caption := ""
	if strings.EqualFold(strings.TrimSpace(title), "img") {
		if meta, ok := parseAttachmentMeta(content); ok {
			name = strings.TrimSpace(meta.name)
			ext = extFromNameOrMime(name, meta.mime)
			if name == "" {
				name = meta.hashHex
			}
			caption = strings.TrimSpace(meta.caption)
			n.persistInboundAttachmentAsync(src, prefix, name, ext, meta.hashHex, tsUnix, to)
		}
	}

	filename := ""
	if name == "" {
		filename = prefix + ".txt"
	} else {
		name = sanitizeMessageName(name)
		if name == "" {
			name = "file"
		}
		if ext != "" && !strings.HasSuffix(strings.ToLower(name), ext) {
			name += ext
		}
		filename = prefix + " " + name
	}

	// For attachment messages, store caption as a regular text message (optional).
	if name != "" && caption != "" {
		capPath := uniquePath(filepath.Join(dir, prefix+".txt"))
		_ = os.WriteFile(capPath, []byte(caption), 0o644)
		n.setInboundMessageFileTags(capPath, tsUnix, src, to)
		return
	}

	path := uniquePath(filepath.Join(dir, filename))
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		rns.Logf(rns.LOG_WARNING, "runcore: persist inbound message: %v", err)
		return
	}
	n.setInboundMessageFileTags(path, tsUnix, src, to)
}

func (n *Node) ensureMessagesDirFromTag(dir string, from string) {
	if n == nil {
		return
	}
	dir = strings.TrimSpace(dir)
	from = strings.ToLower(strings.TrimSpace(from))
	if dir == "" || from == "" {
		return
	}
	if hasXattrTag(dir, messagesFromXattr) {
		return
	}
	_ = setXattrTag(dir, messagesFromXattr, []byte(from))
}

func (n *Node) setInboundMessageFileTags(path string, tsUnix int64, from string, to string) {
	if n == nil {
		return
	}
	path = strings.TrimSpace(path)
	if path == "" {
		return
	}
	from = strings.ToLower(strings.TrimSpace(from))
	to = strings.ToLower(strings.TrimSpace(to))
	_ = setXattrTag(path, messageDateXattr, []byte(strconv.FormatInt(tsUnix, 10)))
	if from != "" {
		_ = setXattrTag(path, messagesFromXattr, []byte(from))
	}
	_ = setXattrTag(path, messageStatusXattr, []byte(messageStatusUnseen))
	if to != "" {
		_ = setXattrTag(path, messageToXattr, []byte(to))
	}
}

func messageTime(m *lxmf.LXMessage) time.Time {
	if m == nil {
		return time.Now()
	}
	if m.Timestamp > 0 {
		sec := int64(m.Timestamp)
		nsec := int64((m.Timestamp - float64(sec)) * 1e9)
		if nsec < 0 {
			nsec = 0
		}
		return time.Unix(sec, nsec)
	}
	return time.Now()
}

func formatMessageMinute(t time.Time) string {
	// User wants "2025-12-21 17꞉45" with U+A789 for time separator.
	return t.Format("2006-01-02 15") + "꞉" + t.Format("04")
}

func sanitizeMessageName(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return ""
	}
	name = filepath.Base(name)
	name = strings.Map(func(r rune) rune {
		switch r {
		case 0, '/', '\\', ':':
			return '-'
		default:
			if r < 32 {
				return -1
			}
			return r
		}
	}, name)
	name = strings.TrimSpace(name)
	if name == "" {
		return ""
	}
	if len(name) > 180 {
		name = name[:180]
	}
	return name
}

func uniquePath(path string) string {
	if _, err := os.Stat(path); err != nil {
		return path
	}
	ext := filepath.Ext(path)
	base := strings.TrimSuffix(filepath.Base(path), ext)
	dir := filepath.Dir(path)
	for i := 2; i < 10_000; i++ {
		p := filepath.Join(dir, fmt.Sprintf("%s #%d%s", base, i, ext))
		if _, err := os.Stat(p); err != nil {
			return p
		}
	}
	return path
}

type attachmentMeta struct {
	hashHex string
	mime    string
	name    string
	caption string
}

func parseAttachmentMeta(content string) (attachmentMeta, bool) {
	var meta attachmentMeta
	for _, line := range strings.Split(content, "\n") {
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key := strings.ToLower(strings.TrimSpace(k))
		val := strings.TrimSpace(v)
		switch key {
		case "hash":
			meta.hashHex = strings.ToLower(val)
		case "mime":
			meta.mime = val
		case "name":
			meta.name = val
		case "caption":
			meta.caption = val
		}
	}
	if meta.hashHex == "" {
		return attachmentMeta{}, false
	}
	return meta, true
}

func extFromNameOrMime(name, mime string) string {
	name = strings.TrimSpace(name)
	if name != "" {
		if ext := strings.ToLower(filepath.Ext(name)); ext != "" && ext != "." {
			return ext
		}
	}
	mime = strings.ToLower(strings.TrimSpace(mime))
	switch mime {
	case "image/jpeg", "image/jpg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/heic", "image/heif":
		return ".heic"
	case "image/webp":
		return ".webp"
	default:
		return ""
	}
}
