import Foundation
import Combine

@MainActor
final class ReticulumDiscoveredPeerStore: ObservableObject {
    static let shared = ReticulumDiscoveredPeerStore()

    @Published private(set) var peers: [ReticulumDiscoveredPeer] = []

    private init() {}

    func discover(
        destinationHash: String,
        displayName: String?,
        seenAt: Date = Date()
    ) {
        let cleanedHash = destinationHash
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        if let index = peers.firstIndex(
            where: { $0.destinationHash == cleanedHash }
        ) {
            let existing = peers[index]

            peers[index] = ReticulumDiscoveredPeer(
                id: existing.id,
                destinationHash: existing.destinationHash,
                displayName: displayName ?? existing.displayName,
                firstSeenAt: existing.firstSeenAt,
                lastSeenAt: seenAt
            )
        } else {
            peers.insert(
                ReticulumDiscoveredPeer(
                    destinationHash: cleanedHash,
                    displayName: displayName,
                    firstSeenAt: seenAt,
                    lastSeenAt: seenAt
                ),
                at: 0
            )
        }

        peers.sort {
            $0.lastSeenAt > $1.lastSeenAt
        }
    }

    func remove(
        destinationHash: String
    ) {
        peers.removeAll {
            $0.destinationHash ==
            destinationHash
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()
        }
    }

    func clear() {
        peers.removeAll()
    }
}
