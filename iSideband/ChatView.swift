import SwiftUI

struct ChatView: View {
    @ObservedObject var bluetooth: BluetoothManager
    @StateObject private var lxmf = LXMFService()

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
                    // Attachment choices will be connected next.
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

                    lxmf.send(
                        text: trimmedMessage,
                        destination: title
                    )
                    message = ""
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            Circle()
                                .fill(
                                    message.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ).isEmpty
                                    ? Color.gray.opacity(0.35)
                                    : Color.accentColor
                                )
                                .animation(.easeInOut(duration: 0.2), value: message)
                        )
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
        .onAppear {
            lxmf.start()
        }
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
