import SwiftUI

struct ChatView: View {
    @ObservedObject var bluetooth: BluetoothManager

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
                TextField("Message", text: $message)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let trimmedMessage = message.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                    guard !trimmedMessage.isEmpty else {
                        return
                    }

                    messages.append(
                        Message(
                            text: trimmedMessage,
                            isMine: true
                        )
                    )

                    bluetooth.sendMessage(trimmedMessage)
                    message = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(
                    message.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundStyle(isMine ? .white : .primary)
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
