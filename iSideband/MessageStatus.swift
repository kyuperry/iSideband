import Foundation

enum MessageStatus: String, Codable, Hashable {
    case queued
    case sending
    case sent
    case delivered
    case received
    case failed
}
