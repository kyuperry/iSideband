import Foundation
import Combine

struct GroupWireEnvelope: Codable {
    static let prefix = "isideband-group-v1:"

    let groupID: UUID
    let groupName: String
    let groupSystemImage: String
    let memberDestinationHashes: [String]
    let logicalMessageID: UUID
    let body: String

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return Self.prefix + data.base64EncodedString()
    }

    static func decode(_ value: String) -> Self? {
        guard value.hasPrefix(prefix),
              let data = Data(base64Encoded: String(value.dropFirst(prefix.count))) else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

@MainActor
final class GroupMessageStore: ObservableObject {
    static let shared = GroupMessageStore()
    @Published private(set) var revision = 0

    private init() {}

    func messages(for groupID: UUID) -> [Message] {
        guard let data = UserDefaults.standard.data(forKey: messageKey(groupID)),
              let messages = try? JSONDecoder().decode([Message].self, from: data) else {
            return []
        }
        return messages
    }

    func save(_ messages: [Message], for groupID: UUID) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: messageKey(groupID))
        revision &+= 1
    }

    @discardableResult
    func receive(
        envelope: GroupWireEnvelope,
        sourceHash: String,
        timestamp: Date,
        attachmentPath: String?,
        attachmentName: String?,
        attachmentMIME: String?,
        attachmentType: Int32
    ) -> Bool {
        guard envelope.memberDestinationHashes.count <= 9 else {
            privacySafeLog("GROUP RECEIVE REJECTED: member limit exceeded")
            return false
        }
        ensureGroupExists(envelope)
        var stored = messages(for: envelope.groupID)
        guard !stored.contains(where: { $0.id == envelope.logicalMessageID }) else {
            return false
        }
        let type: MessageType = attachmentPath == nil ? .text
            : (attachmentType == 1 ? .photo
                : (attachmentMIME?.hasPrefix("audio/") == true ? .voiceNote : .file))
        var size: Int?
        if let attachmentPath,
           let attributes = try? FileManager.default.attributesOfItem(atPath: attachmentPath),
           let number = attributes[.size] as? NSNumber {
            size = number.intValue
        }
        stored.append(Message(
            id: envelope.logicalMessageID,
            text: envelope.body,
            isMine: false,
            senderDisplayName: LXMFContactStore.shared.contact(for: sourceHash)?.displayName,
            senderDestinationHash: sourceHash,
            type: type,
            attachmentName: attachmentName,
            attachmentPath: attachmentPath,
            attachmentSize: size,
            status: .received,
            createdAt: timestamp,
            receivedAt: Date()
        ))
        save(stored, for: envelope.groupID)
        privacySafeLog("GROUP RECEIVE group=\(envelope.groupID) sender=\(sourceHash.prefix(8))")
        return true
    }

    private func ensureGroupExists(_ envelope: GroupWireEnvelope) {
        let key = "savedGroupConversations"
        var groups: [GroupConversation] = []
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([GroupConversation].self, from: data) {
            groups = decoded
        }
        guard !groups.contains(where: { $0.id == envelope.groupID }) else { return }
        groups.append(GroupConversation(
            id: envelope.groupID,
            name: envelope.groupName,
            systemImage: envelope.groupSystemImage,
            memberDestinationHashes: Array(envelope.memberDestinationHashes.prefix(9))
        ))
        if let data = try? JSONEncoder().encode(groups) {
            UserDefaults.standard.set(data, forKey: key)
            revision &+= 1
        }
    }

    private func messageKey(_ groupID: UUID) -> String {
        "groupMessages-\(groupID.uuidString)"
    }
}
