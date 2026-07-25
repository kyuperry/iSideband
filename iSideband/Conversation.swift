import Foundation

struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var lastMessage: String
    var lastActivity: Date
    var unreadCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        lastMessage: String = "",
        lastActivity: Date = .now,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.lastActivity = lastActivity
        self.unreadCount = unreadCount
    }
}
