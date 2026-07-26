import SwiftUI

struct ChatView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @ObservedObject private var lxmfManager = LXMFManager.shared

    let title: String

    @State private var message = ""

    @State private var messages: [Message] = [
        Message(
            text: "RNode connection established.",
            isMine: false
        ),
        Message(
            text: "Ready to send messages.",
            isMine: true
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(messages) { message in
                        messageBubble(
                            text: message.text,
                            isMine: message.isMine
                        )
                    }
                }
                .padding()
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    // Attachment choices will be connected later.
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)

                TextField("Message", text: $message)
                    .textFieldStyle(.roundedBorder)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            Circle()
                                .fill(
                                    trimmedMessage.isEmpty
                                    ? Color.gray.opacity(0.35)
                                    : Color.accentColor
                                )
                                .animation(
                                    .easeInOut(duration: 0.2),
                                    value: message
                                )
                        )
                }
                .disabled(trimmedMessage.isEmpty)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            lxmfManager.start()
        }
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func sendMessage() {
        guard !trimmedMessage.isEmpty else {
            return
        }

        let peer = LXMFPeer(
            displayName: title,
            destinationHash:
                "0123456789abcdef0123456789abcdef"
        )

        guard let queuedMessage = lxmfManager.send(
            text: trimmedMessage,
            to: peer
        ) else {
            print("ChatView could not queue LXMF message")
            return
        }

        _ = queuedMessage

        messages.append(
            Message(
                text: trimmedMessage,
                isMine: true
            )
        )

        message = ""
    }

    private func messageBubble(
        text: String,
        isMine: Bool
    ) -> some View {
        HStack {
            if isMine {
                Spacer()
            }

            Text(text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isMine
                    ? Color.accentColor
                    : Color.secondary.opacity(0.15)
                )
                .foregroundStyle(
                    isMine ? .white : .primary
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 18)
                )

            if !isMine {
                Spacer()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(
            bluetooth: BluetoothManager(),
            title: "Camp Node"
        )
    }
}
