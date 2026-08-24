import Foundation

struct ReticulumDiscoveredPeer: Identifiable, Codable, Hashable {
    let id: UUID
    let destinationHash: String
    let displayName: String?
    let announcedHops: UInt8?
    let firstSeenAt: Date
    let lastSeenAt: Date

    init(
        id: UUID = UUID(),
        destinationHash: String,
        displayName: String?,
        announcedHops: UInt8? = nil,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = id

        self.destinationHash = destinationHash
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        self.displayName = displayName?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        self.announcedHops = announcedHops

        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }

    var resolvedDisplayName: String {
        guard
            let displayName,
            !displayName.isEmpty
        else {
            return "Unknown Node"
        }

        return displayName
    }
}
