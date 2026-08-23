import Foundation

struct Message: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let isMine: Bool
    let senderDisplayName: String?
    let senderDestinationHash: String?
    let type: MessageType
    let attachmentName: String?
    let attachmentPath: String?
    let attachmentSize: Int?
    let status: MessageStatus
    let createdAt: Date
    let deliveredAt: Date?
    let receivedAt: Date?
    let outgoingMessageIDs: [UUID]

    init(
        id: UUID = UUID(),
        text: String,
        isMine: Bool,
        senderDisplayName: String? = nil,
        senderDestinationHash: String? = nil,
        type: MessageType = .text,
        attachmentName: String? = nil,
        attachmentPath: String? = nil,
        attachmentSize: Int? = nil,
        status: MessageStatus? = nil,
        createdAt: Date = Date(),
        deliveredAt: Date? = nil,
        receivedAt: Date? = nil,
        outgoingMessageIDs: [UUID] = []
    ) {
        self.id = id
        self.text = text
        self.isMine = isMine
        self.senderDisplayName = senderDisplayName
        self.senderDestinationHash = senderDestinationHash
        self.type = type
        self.attachmentName = attachmentName
        self.attachmentPath = attachmentPath
        self.attachmentSize = attachmentSize
        self.status = status ?? (isMine ? .queued : .received)
        self.createdAt = createdAt
        self.deliveredAt = deliveredAt
        self.receivedAt = receivedAt
        self.outgoingMessageIDs = outgoingMessageIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case isMine
        case senderDisplayName
        case senderDestinationHash
        case type
        case attachmentName
        case attachmentPath
        case attachmentSize
        case status
        case createdAt
        case deliveredAt
        case receivedAt
        case outgoingMessageIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        isMine = try container.decode(Bool.self, forKey: .isMine)
        senderDisplayName = try container.decodeIfPresent(
            String.self,
            forKey: .senderDisplayName
        )
        senderDestinationHash = try container.decodeIfPresent(
            String.self,
            forKey: .senderDestinationHash
        )

        type = try container.decodeIfPresent(
            MessageType.self,
            forKey: .type
        ) ?? .text
        attachmentName = try container.decodeIfPresent(
            String.self,
            forKey: .attachmentName
        )

        attachmentPath = try container.decodeIfPresent(
            String.self,
            forKey: .attachmentPath
        )

        attachmentSize = try container.decodeIfPresent(
            Int.self,
            forKey: .attachmentSize
        )
        
        status = try container.decodeIfPresent(
            MessageStatus.self,
            forKey: .status
        ) ?? (isMine ? .sent : .received)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        deliveredAt = try container.decodeIfPresent(Date.self, forKey: .deliveredAt)
        receivedAt = try container.decodeIfPresent(Date.self, forKey: .receivedAt)
        outgoingMessageIDs = try container.decodeIfPresent([UUID].self, forKey: .outgoingMessageIDs) ?? []
    }
}
