import Foundation

struct Message: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let isMine: Bool

    init(
        id: UUID = UUID(),
        text: String,
        isMine: Bool
    ) {
        self.id = id
        self.text = text
        self.isMine = isMine
    }
}
