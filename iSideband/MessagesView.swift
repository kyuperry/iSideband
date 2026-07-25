import SwiftUI

struct ChatMessage: Identifiable, Codable {
    let id = UUID()
    let text: String
    let date: Date
    let isOutgoing: Bool
    let status: String?
}

struct MessagesView: View {
    @ObservedObject var bluetooth: BluetoothManager

    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var showingAttachmentMenu = false
    

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "message")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)

                    Text("No Messages")
                        .font(.title2.bold())

                    Text("Messages sent here are currently raw radio-data tests.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { message in
                                messageBubble(message)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("BOTTOM")
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        withAnimation {
                            proxy.scrollTo("BOTTOM", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                
                Button {
                    showingAttachmentMenu = true
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
                TextField(
                    "Message",
                    text: $messageText,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)

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
                                    messageText.trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    ).isEmpty
                                    ? Color.gray.opacity(0.35)
                                    : Color.accentColor
                                )
                        )
                }
                .disabled(
                    messageText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
            .padding()
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Add Attachment",
            isPresented: $showingAttachmentMenu,
            titleVisibility: .visible
        ) {
            Button("Choose Photo") {
                print("Choose Photo selected")
            }

            Button("Take Photo") {
                print("Take Photo selected")
            }

            Button("Choose File") {
                print("Choose File selected")
            }

            Button("Voice Note — Coming Soon") { }
                .disabled(true)

            Button("Share Location — Coming Soon") { }
                .disabled(true)

            Button("Cancel", role: .cancel) { }
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else {
            return
        }

        bluetooth.sendMessage(trimmed)

        messages.append(
            ChatMessage(
                text: trimmed,
                date: Date(),
                isOutgoing: true,
                status: "Sent to RNode"
            )
        )

        messageText = ""
    }

    private func messageBubble(
        _ message: ChatMessage
    ) -> some View {
        HStack {
            if message.isOutgoing {
                Spacer()
            }

            VStack(
                alignment: message.isOutgoing
                    ? .trailing
                    : .leading,
                spacing: 4
            ) {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isOutgoing
                            ? Color.accentColor
                            : Color.secondary.opacity(0.2)
                    )
                    .foregroundStyle(
                        message.isOutgoing
                            ? .white
                            : .primary
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18)
                    )

                HStack(spacing: 5) {
                    Text(
                        message.date.formatted(
                            date: .omitted,
                            time: .shortened
                        )
                    )

                    if let status = message.status {
                        Text("•")
                        Text(status)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if !message.isOutgoing {
                Spacer()
            }
        }
    }
}

#Preview {
    NavigationStack {
        MessagesView(
            bluetooth: BluetoothManager()
        )
    }
}
