import SwiftUI

enum StatusQuickMessage: String, CaseIterable, Identifiable {
    case statusCheck = "Status Check"
    case inContact = "In Contact"
    case regroupOnMe = "Regroup on me"
    case emergency = "Emergency"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .statusCheck: "questionmark.circle.fill"
        case .inContact: "checkmark.circle.fill"
        case .regroupOnMe: "person.3.fill"
        case .emergency: "exclamationmark.triangle.fill"
        }
    }
}

struct MessageComposer: View {
    @Environment(\.nightVisionModeEnabled) private var isNightVisionEnabled
    @State private var isShowingAttachmentPicker = false
    @State private var isShowingStatusMessages = false
    @Binding var messageText: String
    @FocusState.Binding var isFocused: Bool

    let showsPushToTalk: Bool
    let onPhotoTapped: () -> Void
    let onFileTapped: () -> Void
    let onPushToTalkTapped: () -> Void
    let onStatusTapped: (String) -> Void
    let onSendTapped: () -> Void

    private var canSend: Bool {
        !messageText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                isShowingAttachmentPicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(
                        isNightVisionEnabled
                            ? NightVisionPalette.primary
                            : Color.primary
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(
                                isNightVisionEnabled
                                    ? NightVisionPalette.surface
                                    : Color.secondary.opacity(0.15)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add attachment")
            .popover(isPresented: $isShowingAttachmentPicker) {
                attachmentPicker
                    .presentationCompactAdaptation(.popover)
            }

            Button {
                onPushToTalkTapped()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(
                        isNightVisionEnabled
                            ? NightVisionPalette.primary
                            : Color.primary
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(
                                isNightVisionEnabled
                                    ? NightVisionPalette.surface
                                    : Color.secondary.opacity(0.15)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Push to Talk")
            .accessibilityHint("Opens the push-to-talk recorder")

            TextField(
                "Message",
                text: $messageText,
                axis: .vertical
            )
            .focused($isFocused)
            .foregroundStyle(
                isNightVisionEnabled
                    ? NightVisionPalette.primary
                    : Color.primary
            )
            .tint(
                isNightVisionEnabled
                    ? NightVisionPalette.primary
                    : Color.accentColor
            )
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isNightVisionEnabled
                    ? NightVisionPalette.field
                    : Color.secondary.opacity(0.12)
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
                    .foregroundStyle(
                        isNightVisionEnabled
                            ? NightVisionPalette.primary
                            : .white
                    )
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(
                                isNightVisionEnabled
                                    ? (canSend
                                        ? NightVisionPalette.strongSurface
                                        : NightVisionPalette.disabled)
                                    : (canSend
                                        ? Color.accentColor
                                        : Color.gray.opacity(0.35))
                            )
                    )
            }
            .disabled(!canSend)
        }
        .padding()
    }

    private var attachmentPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            attachmentButton("Photo", systemImage: "photo.fill") {
                onPhotoTapped()
            }
            attachmentButton("File", systemImage: "doc.fill") {
                onFileTapped()
            }
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isShowingStatusMessages.toggle()
                }
            } label: {
                HStack {
                    Label("Status", systemImage: "bolt.horizontal.circle.fill")
                    Spacer()
                    Image(
                        systemName: isShowingStatusMessages
                            ? "chevron.up"
                            : "chevron.down"
                    )
                    .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                isNightVisionEnabled
                    ? NightVisionPalette.primary
                    : Color.primary
            )

            if isShowingStatusMessages {
                Divider().padding(.horizontal, 12)
                ForEach(StatusQuickMessage.allCases) { message in
                    statusButton(message)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 190)
        .background(
            isNightVisionEnabled
                ? NightVisionPalette.field
                : Color(.systemBackground)
        )
    }

    private func statusButton(
        _ message: StatusQuickMessage
    ) -> some View {
        Button {
            isShowingStatusMessages = false
            isShowingAttachmentPicker = false
            onStatusTapped(message.rawValue)
        } label: {
            Label(message.rawValue, systemImage: message.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            message == .emergency && !isNightVisionEnabled
                ? Color.red
                : (isNightVisionEnabled
                    ? NightVisionPalette.primary
                    : Color.primary)
        )
    }

    private func attachmentButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            isShowingAttachmentPicker = false
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isNightVisionEnabled
                ? NightVisionPalette.primary
                : Color.primary
        )
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
            onPhotoTapped: { },
            onFileTapped: { },
            onPushToTalkTapped: { },
            onStatusTapped: { _ in },
            onSendTapped: { }
        )
    }
}
