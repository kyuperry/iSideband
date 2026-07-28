import Combine
import Foundation

@MainActor
final class LXMFIncomingMessageStore: ObservableObject {
    static let shared = LXMFIncomingMessageStore()

    @Published private(set) var revision = 0

    private init() {}

    @discardableResult
    func save(
        _ message: LXMFIncomingMessage
    ) -> Bool {
        let key =
            "savedDirectMessages." +
            message.sourceHashHex
        var messages = load(key: key)
        let messageHash = message.id.map {
            String(format: "%02x", $0)
        }.joined()

        guard !messages.contains(
            where: { $0.lxmfHash == messageHash }
        ) else {
            return false
        }

        messages.append(
            ChatMessage(
                text: message.content,
                date: message.timestamp,
                isOutgoing: false,
                status: "Received",
                lxmfHash: messageHash
            )
        )
        messages.sort { $0.date < $1.date }

        guard let data = try? JSONEncoder().encode(
            messages
        ) else {
            return false
        }

        UserDefaults.standard.set(data, forKey: key)
        revision += 1
        return true
    }

    private func load(
        key: String
    ) -> [ChatMessage] {
        guard let data = UserDefaults.standard.data(
                    forKey: key
              ),
              let messages = try? JSONDecoder().decode(
                    [ChatMessage].self,
                    from: data
              )
        else {
            return []
        }
        return messages
    }
}
