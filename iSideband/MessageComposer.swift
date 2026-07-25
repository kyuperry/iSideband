import SwiftUI

struct MessageComposer: View {
    @Binding var messageText: String

    let onAttachmentTapped: () -> Void
    let onSendTapped: () -> Void

    private var canSend: Bool {
        !messageText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                onAttachmentTapped()
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(
                                Color.secondary.opacity(0.15)
                            )
                    )
            }
            .buttonStyle(.plain)

            TextField(
                "Message",
                text: $messageText,
                axis: .vertical
            )
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
    MessageComposer(
        messageText: .constant("Hello"),
        onAttachmentTapped: { },
        onSendTapped: { }
    )
}
