import Foundation

struct Message: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let isMine: Bool
    let type: MessageType
    let attachmentName: String?
    let attachmentPath: String?
    let attachmentSize: Int?
    let status: MessageStatus

    init(
        id: UUID = UUID(),
        text: String,
        isMine: Bool,
        type: MessageType = .text,
        attachmentName: String? = nil,
        attachmentPath: String? = nil,
        attachmentSize: Int? = nil,
        status: MessageStatus? = nil
    ) {
        self.id = id
        self.text = text
        self.isMine = isMine
        self.type = type
        self.attachmentName = attachmentName
        self.attachmentPath = attachmentPath
        self.attachmentSize = attachmentSize
        self.status = status ?? (isMine ? .queued : .received)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case isMine
        case type
        case attachmentName
        case attachmentPath
        case attachmentSize
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        isMine = try container.decode(Bool.self, forKey: .isMine)

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
    }
}
