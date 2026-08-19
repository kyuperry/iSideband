import SwiftUI

struct MessageComposer: View {
    @Binding var messageText: String
    @FocusState.Binding var isFocused: Bool

    let showsPushToTalk: Bool
    let isPushToTalkRecording: Bool
    let onPhotoTapped: () -> Void
    let onFileTapped: () -> Void
    let onVoiceTapped: () -> Void
    let onPushToTalkTapped: () -> Void
    let onSendTapped: () -> Void

    private var canSend: Bool {
        !messageText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                Button(action: onPhotoTapped) {
                    Label("Photo", systemImage: "photo.fill")
                }
                .disabled(isPushToTalkRecording)

                Button(action: onFileTapped) {
                    Label("File", systemImage: "doc.fill")
                }
                .disabled(isPushToTalkRecording)

                Button(action: onVoiceTapped) {
                    Label("Voice", systemImage: "waveform")
                }
                .disabled(isPushToTalkRecording)

                if showsPushToTalk {
                    Divider()
                    Button(action: onPushToTalkTapped) {
                        Label(
                            isPushToTalkRecording ? "Stop PTT" : "Push to Talk",
                            systemImage: isPushToTalkRecording
                                ? "stop.fill"
                                : "mic.fill"
                        )
                    }
                }
            } label: {
                Image(
                    systemName: isPushToTalkRecording
                        ? "mic.fill"
                        : "plus"
                )
                    .font(.headline.weight(.bold))
                    .foregroundStyle(
                        isPushToTalkRecording ? Color.red : Color.primary
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(
                                Color.secondary.opacity(0.15)
                            )
                    )
            }
            .menuOrder(.fixed)
            .accessibilityLabel("Add attachment")

            TextField(
                "Message",
                text: $messageText,
                axis: .vertical
            )
            .focused($isFocused)
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color.secondary.opacity(0.12)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )

            Button {
                onSendTapped()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(
                                canSend
                                    ? Color.accentColor
                                    : Color.gray.opacity(0.35)
                            )
                    )
            }
            .disabled(!canSend)
        }
        .padding()
    }
}

#Preview {
    MessageComposerPreview()
}

private struct MessageComposerPreview: View {
    @FocusState private var isFocused: Bool

    var body: some View {
        MessageComposer(
            messageText: .constant("Hello"),
            isFocused: $isFocused,
            showsPushToTalk: true,
            isPushToTalkRecording: false,
            onPhotoTapped: { },
            onFileTapped: { },
            onVoiceTapped: { },
            onPushToTalkTapped: { },
            onSendTapped: { }
        )
    }
}
