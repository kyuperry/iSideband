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
        let key = readStorageKey(destinationHash)
        let lastRead: Date
        if let data = MessageDatabase.shared.data(forKey: key),
           let date = try? JSONDecoder().decode(Date.self, from: data) {
            lastRead = date
        } else {
            lastRead = UserDefaults.standard.object(forKey: key)
                as? Date ?? .distantPast
        }

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
        let key = readStorageKey(destinationHash)
        let date = Date()
        if let data = try? JSONEncoder().encode(date),
           MessageDatabase.shared.set(data, forKey: key) {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(date, forKey: key)
        }
        revision += 1
    }

    func deleteConversation(
        destinationHash: String
    ) {
        let messageKey = messageStorageKey(destinationHash)
        let readKey = readStorageKey(destinationHash)
        MessageDatabase.shared.removeValue(forKey: messageKey)
        MessageDatabase.shared.removeValue(forKey: readKey)
        UserDefaults.standard.removeObject(forKey: messageKey)
        UserDefaults.standard.removeObject(forKey: readKey)
        revision += 1
    }

    @discardableResult
    func replaceMessages(
        _ messages: [ChatMessage],
        for destinationHash: String
    ) -> Bool {
        persist(
            messages.sorted { $0.date < $1.date },
            key: messageStorageKey(destinationHash)
        )
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

        if let existingIndex = messages.firstIndex(
            where: { $0.lxmfHash == messageHash }
        ) {
            guard messages[existingIndex].attachmentPath == nil,
                  message.attachmentPath != nil,
                  let savedAttachment = persistAttachment(from: message)
            else {
                return false
            }
            let existing = messages[existingIndex]
            messages[existingIndex] = ChatMessage(
                id: existing.id,
                text: message.content.isEmpty ? existing.text : message.content,
                date: existing.date,
                sentAt: existing.sentAt ?? message.timestamp,
                receivedAt: existing.receivedAt ?? Date(),
                isOutgoing: false,
                status: "Received",
                lxmfMessageID: existing.lxmfMessageID,
                lxmfHash: existing.lxmfHash,
                type: directMessageType(for: message),
                attachmentName: savedAttachment.lastPathComponent,
                attachmentPath: savedAttachment.path,
                attachmentSize: attachmentSize(at: savedAttachment)
            )
            return persist(messages, key: key)
        }

        let savedAttachment = persistAttachment(from: message)
        let receivedAt = Date()
        let displayDate = nextConversationDate(after: messages)
        messages.append(
            ChatMessage(
                text: message.content,
                date: displayDate,
                sentAt: message.timestamp,
                receivedAt: receivedAt,
                isOutgoing: false,
                status: "Received",
                lxmfHash: messageHash,
                type: directMessageType(for: message),
                attachmentName: savedAttachment?.lastPathComponent ?? message.attachmentName,
                attachmentPath: savedAttachment?.path,
                attachmentSize: savedAttachment.flatMap {
                    attachmentSize(at: $0)
                }
            )
        )

        return persist(messages, key: key)
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
            privacySafeLog("Could not persist incoming attachment: \(error)")
            return nil
        }
    }

    private func directMessageType(
        for message: LXMFIncomingMessage
    ) -> DirectMessageType {
        switch message.attachmentType {
        case .photo: return .photo
        case .file: return .file
        case .voiceNote: return .voiceNote
        case nil: return .text
        }
    }

    private func load(
        key: String
    ) -> [ChatMessage] {
        let legacyData = UserDefaults.standard.data(forKey: key)
        let storedData = MessageDatabase.shared.data(forKey: key)
            ?? legacyData
        guard let data = storedData,
              let messages = try? JSONDecoder().decode(
                    [ChatMessage].self,
                    from: data
              )
        else {
            return []
        }
        let repaired = messages.map(repairAttachmentPath)
        if let repairedData = try? JSONEncoder().encode(repaired),
           (legacyData != nil || repaired != messages),
           MessageDatabase.shared.set(repairedData, forKey: key) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return repaired
    }

    private func repairAttachmentPath(_ message: ChatMessage) -> ChatMessage {
        guard let storedPath = message.attachmentPath,
              !FileManager.default.fileExists(atPath: storedPath),
              let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
              ).first
        else {
            return message
        }

        let fileName = URL(fileURLWithPath: storedPath).lastPathComponent
        let candidates = [
            documents.appendingPathComponent(
                "DirectAttachments/Incoming/\(fileName)"
            ),
            documents.appendingPathComponent(
                "DirectAttachments/\(fileName)"
            )
        ]
        guard let repairedURL = candidates.first(
            where: { FileManager.default.fileExists(atPath: $0.path) }
        ) else {
            return message
        }

        return ChatMessage(
            id: message.id,
            text: message.text,
            date: message.date,
            sentAt: message.sentAt,
            receivedAt: message.receivedAt,
            isOutgoing: message.isOutgoing,
            status: message.status,
            lxmfMessageID: message.lxmfMessageID,
            lxmfHash: message.lxmfHash,
            type: message.type,
            attachmentName: message.attachmentName,
            attachmentPath: repairedURL.path,
            attachmentSize: message.attachmentSize
        )
    }

    private func attachmentSize(at url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.size] as? NSNumber)?.intValue
    }

    private func nextConversationDate(
        after messages: [ChatMessage]
    ) -> Date {
        guard let latest = messages.map(\.date).max() else {
            return Date()
        }
        return max(
            Date(),
            latest.addingTimeInterval(0.001)
        )
    }

    private func persist(
        _ messages: [ChatMessage],
        key: String
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(messages) else {
            return false
        }
        if !MessageDatabase.shared.set(data, forKey: key) {
            UserDefaults.standard.set(data, forKey: key)
        }
        revision += 1
        return true
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
