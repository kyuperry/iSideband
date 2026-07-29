import Combine
import Foundation

@MainActor
final class LXMFIncomingMessageStore: ObservableObject {
    static let shared = LXMFIncomingMessageStore()

    @Published private(set) var revision = 0

    private init() {}

    func messages(
        for destinationHash: String
    ) -> [ChatMessage] {
        load(
            key: messageStorageKey(
                destinationHash
            )
        )
    }

    func latestMessage(
        for destinationHash: String
    ) -> ChatMessage? {
        messages(for: destinationHash).last
    }

    func unreadCount(
        for destinationHash: String
    ) -> Int {
        let lastRead = UserDefaults.standard.object(
            forKey: readStorageKey(
                destinationHash
            )
        ) as? Date ?? .distantPast

        return messages(for: destinationHash)
            .filter {
                !$0.isOutgoing &&
                $0.date > lastRead
            }
            .count
    }

    func markRead(
        destinationHash: String
    ) {
        UserDefaults.standard.set(
            Date(),
            forKey: readStorageKey(
                destinationHash
            )
        )
        revision += 1
    }

    func deleteConversation(
        destinationHash: String
    ) {
        UserDefaults.standard.removeObject(
            forKey: messageStorageKey(
                destinationHash
            )
        )
        UserDefaults.standard.removeObject(
            forKey: readStorageKey(
                destinationHash
            )
        )
        revision += 1
    }

    @discardableResult
    func save(
        _ message: LXMFIncomingMessage
    ) -> Bool {
        let key =
            messageStorageKey(
                message.sourceHashHex
            )
        var messages = load(key: key)
        let messageHash = message.id.map {
            String(format: "%02x", $0)
        }.joined()

        guard !messages.contains(
            where: { $0.lxmfHash == messageHash }
        ) else {
            return false
        }

        let savedAttachment = persistAttachment(from: message)
        messages.append(
            ChatMessage(
                text: message.content,
                date: message.timestamp,
                isOutgoing: false,
                status: "Received",
                lxmfHash: messageHash,
                type: message.attachmentType == .photo ? .photo :
                    (message.attachmentType == .file ? .file : .text),
                attachmentName: savedAttachment?.lastPathComponent ?? message.attachmentName,
                attachmentPath: savedAttachment?.path,
                attachmentSize: savedAttachment.flatMap {
                    (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? NSNumber)?.intValue
                }
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

    private func persistAttachment(from message: LXMFIncomingMessage) -> URL? {
        guard let sourcePath = message.attachmentPath else { return nil }
        let source = URL(fileURLWithPath: sourcePath)
        guard FileManager.default.fileExists(atPath: source.path),
              let documents = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
              ).first else { return nil }
        let directory = documents.appendingPathComponent(
            "DirectAttachments/Incoming", isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let rawName = message.attachmentName ?? source.lastPathComponent
            let safeName = URL(fileURLWithPath: rawName).lastPathComponent
            let destination = directory.appendingPathComponent(
                message.id.prefix(8).map { String(format: "%02x", $0) }.joined() + "-" + safeName
            )
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: source, to: destination)
            }
            return destination
        } catch {
            print("Could not persist incoming attachment: \(error)")
            return nil
        }
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

    private func messageStorageKey(
        _ destinationHash: String
    ) -> String {
        "savedDirectMessages." +
        destinationHash
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
    }

    private func readStorageKey(
        _ destinationHash: String
    ) -> String {
        "isideband.lxmf.lastRead." +
        destinationHash
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
    }
}
