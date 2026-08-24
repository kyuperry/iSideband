import SwiftUI
import UIKit

struct MessageBubble: View {
    @Environment(\.nightVisionModeEnabled) private var isNightVisionEnabled
    let text: String
    let date: Date
    let sentAt: Date?
    let deliveredAt: Date?
    let receivedAt: Date?
    let isOutgoing: Bool
    let status: String?

    let isPhoto: Bool
    let isFile: Bool
    let isVoiceNote: Bool

    let attachmentName: String?
    let attachmentPath: String?
    let attachmentSize: Int?

    @State private var selectedImage: UIImage?
    @State private var selectedFileURL: URL?
    @State private var isMetadataVisible = false
    @StateObject private var voicePlayer = VoiceNotePlayer()

    init(
        text: String,
        date: Date,
        sentAt: Date? = nil,
        deliveredAt: Date? = nil,
        receivedAt: Date? = nil,
        isOutgoing: Bool,
        status: String?,
        isPhoto: Bool,
        isFile: Bool,
        isVoiceNote: Bool = false,
        attachmentName: String?,
        attachmentPath: String?,
        attachmentSize: Int?
    ) {
        self.text = text
        self.date = date
        self.sentAt = sentAt
        self.deliveredAt = deliveredAt
        self.receivedAt = receivedAt
        self.isOutgoing = isOutgoing
        self.status = status
        self.isPhoto = isPhoto
        self.isFile = isFile
        self.isVoiceNote = isVoiceNote
        self.attachmentName = attachmentName
        self.attachmentPath = attachmentPath
        self.attachmentSize = attachmentSize
    }

    var body: some View {
        HStack {
            if isOutgoing {
                Spacer()
            }

            VStack(
                alignment: isOutgoing
                    ? .trailing
                    : .leading,
                spacing: 4
            ) {
                messageContent

                if status != nil || displayedTimestampText != nil {
                    HStack(spacing: 5) {
                        if let displayedTimestampText {
                            Text(displayedTimestampText)
                        }

                        if let status,
                           !isReplacedByExpandedTimestamp(status) {
                            if displayedTimestampText != nil {
                                Text("•")
                            }
                            Text(status)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(timestampColor)
                    .animation(.easeInOut(duration: 0.18), value: isMetadataVisible)
                }
            }

            if !isOutgoing {
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !hasAttachment else { return }
            toggleMetadata()
        }
        .fullScreenCover(
            isPresented: Binding(
                get: {
                    selectedImage != nil
                },
                set: { isPresented in
                    if !isPresented {
                        selectedImage = nil
                    }
                }
            )
        ) {
            if let selectedImage {
                PhotoViewer(
                    image: selectedImage
                )
            }
        }
        .sheet(
            isPresented: Binding(
                get: {
                    selectedFileURL != nil
                },
                set: { isPresented in
                    if !isPresented {
                        selectedFileURL = nil
                    }
                }
            )
        ) {
            if let selectedFileURL {
                FilePreview(
                    url: selectedFileURL
                )
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if isPhoto,
           let attachmentPath,
           let image = UIImage(
               contentsOfFile: attachmentPath
           ) {
            VStack(
                alignment: .trailing,
                spacing: 4
            ) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .saturation(isNightVisionEnabled ? 0 : 1)
                        .colorMultiply(
                            isNightVisionEnabled
                                ? NightVisionPalette.primary
                                : .white
                        )
                        .brightness(isNightVisionEnabled ? -0.22 : 0)
                        .frame(
                            maxWidth: 260,
                            maxHeight: 320
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18,
                                style: .continuous
                            )
                        )

                    if let attachmentSize {
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount:
                                    Int64(attachmentSize),
                                countStyle: .file
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(timestampColor)
                    }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedImage = image
            }
            .simultaneousGesture(metadataLongPressGesture)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(
                "Tap to open the photo. Press and hold to show delivery details."
            )
        } else if isVoiceNote {
            HStack(spacing: 10) {
                Image(systemName: voiceIconName)
                    .font(.title)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleVoicePlayback()
                    }
                    .simultaneousGesture(metadataLongPressGesture)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(
                        voicePlayer.isPlaying ? "Pause voice message" : "Play voice message"
                    )

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice Message")
                            .font(.subheadline.bold())
                        if isCodec2VoiceNote {
                            Text("Codec2 audio — use High-quality Voice in Sideband")
                                .font(.caption2)
                        } else if let error = voicePlayer.errorMessage {
                            Text(error).font(.caption2)
                        }
                    }
                    Image(systemName: "waveform")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleMetadata()
                }
                .simultaneousGesture(metadataLongPressGesture)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(bubbleColor)
            .foregroundStyle(messageForegroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if isFile {
            fileBubble
                .contentShape(Rectangle())
                .onTapGesture {
                    openFile()
                }
                .simultaneousGesture(metadataLongPressGesture)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(
                    "Tap to open the file. Press and hold to show delivery details."
                )
        } else {
            textBubble
        }
    }

    private var textBubble: some View {
        Text(text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleColor)
            .foregroundStyle(
                messageForegroundColor
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .accessibilityHint(
                "Tap to show or hide delivery details"
            )
    }

    private var fileBubble: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title2)

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(
                    attachmentName
                        ?? "Attachment"
                )
                .font(.subheadline.bold())
                .lineLimit(1)

                if let attachmentSize {
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount:
                                Int64(attachmentSize),
                            countStyle: .file
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        metadataColor
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleColor)
        .foregroundStyle(
            messageForegroundColor
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var bubbleColor: Color {
        if isNightVisionEnabled {
            return isOutgoing
                ? NightVisionPalette.strongSurface
                : NightVisionPalette.surface
        }
        return isOutgoing
            ? Color.accentColor
            : Color.secondary.opacity(0.2)
    }

    private var messageForegroundColor: Color {
        isNightVisionEnabled
            ? NightVisionPalette.primary
            : (isOutgoing ? .white : .primary)
    }

    private var metadataColor: Color {
        isNightVisionEnabled
            ? NightVisionPalette.secondary
            : (isOutgoing ? Color.white.opacity(0.8) : .secondary)
    }

    private var timestampColor: Color {
        isNightVisionEnabled ? NightVisionPalette.secondary : .secondary
    }

    private var hasAttachment: Bool {
        isPhoto || isFile || isVoiceNote
    }

    private func toggleMetadata() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isMetadataVisible.toggle()
        }
    }

    private var metadataLongPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in
                if !isMetadataVisible {
                    toggleMetadata()
                }
            }
    }

    private func toggleVoicePlayback() {
        guard let attachmentPath, isPlayableVoiceNote else { return }
        voicePlayer.toggle(url: URL(fileURLWithPath: attachmentPath))
    }

    private var timestampText: String? {
        if isOutgoing {
            if let deliveredAt {
                return "Delivered \(shortTime(deliveredAt))"
            }
            if status == "Delivered" {
                return "Delivered time unavailable"
            }
            if let sentAt {
                return "Sent \(shortTime(sentAt))"
            }
            return nil
        }

        if let receivedAt {
            return "Received \(shortTime(receivedAt))"
        }
        return "Received \(shortTime(date))"
    }

    private var automaticPhotoTimestampText: String? {
        guard isPhoto else { return nil }
        if isOutgoing {
            if let deliveredAt {
                return "Delivered \(shortTime(deliveredAt))"
            }
            if status == "Delivered" {
                return "Delivered time unavailable"
            }
            return nil
        }
        return "Received \(shortTime(receivedAt ?? date))"
    }

    private var displayedTimestampText: String? {
        if isMetadataVisible {
            return timestampText
        }
        return automaticPhotoTimestampText
    }

    private func shortTime(_ value: Date) -> String {
        value.formatted(date: .omitted, time: .shortened)
    }

    private func isReplacedByExpandedTimestamp(_ status: String) -> Bool {
        guard displayedTimestampText != nil else {
            return false
        }
        return status == "Sent" || status == "Delivered" || status == "Received"
    }

    private var isPlayableVoiceNote: Bool {
        guard let extensionName = attachmentPath.map({
            URL(fileURLWithPath: $0).pathExtension.lowercased()
        }) else {
            return false
        }
        return extensionName == "ogg" || extensionName == "m4a"
    }

    private var isCodec2VoiceNote: Bool {
        attachmentPath?.lowercased().hasSuffix(".c2") == true
    }

    private var voiceIconName: String {
        guard isPlayableVoiceNote else { return "waveform.badge.exclamationmark" }
        return voicePlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill"
    }

    private func openFile() {
        guard let attachmentPath else {
            return
        }

        let fileURL = URL(
            fileURLWithPath: attachmentPath
        )

        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            privacySafeLog(
                "Attachment file is missing: \(fileURL.path)"
            )
            return
        }

        selectedFileURL = fileURL
    }
}
