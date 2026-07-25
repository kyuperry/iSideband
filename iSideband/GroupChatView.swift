import SwiftUI

struct GroupChatView: View {
    let group: GroupConversation

    @State private var messages: [Message]

    init(group: GroupConversation) {
        self.group = group
        _messages = State(
            initialValue: Self.loadMessages(for: group.id)
        )
    }
    @State private var draft = ""

    var body: some View {
        ScrollViewReader { proxy in
            VStack {
                List(messages) { message in
                    HStack {
                        if message.isMine {
                            Spacer()
                        }
                        
                        Text(message.text)
                            .padding(10)
                            .background(
                                message.isMine
                                ? Color.accentColor
                                : Color.gray.opacity(0.2)
                            )
                            .foregroundStyle(
                                message.isMine ? .white : .primary
                            )
                            .clipShape(Capsule())
                        
                        if !message.isMine {
                            Spacer()
                        }
                    }
                    .listRowSeparator(.hidden)
                    .id(message.id)
                }
                .listStyle(.plain)
                .onChange(of: messages) {
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    
                    saveMessages()
                }
                
                HStack {
                    TextField(
                        "Type a message…",
                        text: $draft
                    )
                    
                    Button("Send") {
                        let text = draft.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        
                        guard !text.isEmpty else {
                            return
                        }
                        
                        messages.append(
                            Message(
                                text: text,
                                isMine: true
                            )
                        )
                        
                        
                        draft = ""
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            messages.append(
                                Message(
                                    text: "Received: \(text)",
                                    isMine: false
                                )
                                
                            )
                            
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: messages) {
            saveMessages()
        }
    }
    private static func storageKey(for groupID: UUID) -> String {
        "groupMessages-\(groupID.uuidString)"
    }

    private static func loadMessages(for groupID: UUID) -> [Message] {
        guard
            let data = UserDefaults.standard.data(
                forKey: storageKey(for: groupID)
            ),
            let savedMessages = try? JSONDecoder().decode(
                [Message].self,
                from: data
            )
        else {
            return []
        }

        return savedMessages
    }

    private func saveMessages() {
        guard let data = try? JSONEncoder().encode(messages) else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: Self.storageKey(for: group.id)
        )
    }
}
