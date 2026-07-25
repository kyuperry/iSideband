import Foundation

enum MessageType: String, Codable, Hashable {
    case text
    case photo
    case file
    case voiceNote
    case location
    case call
    case system
}
