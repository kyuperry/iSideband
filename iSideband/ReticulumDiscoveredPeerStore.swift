import Foundation
import Combine

@MainActor
final class ReticulumDiscoveredPeerStore: ObservableObject {
    static let shared = ReticulumDiscoveredPeerStore()

    @Published private(set) var peers: [ReticulumDiscoveredPeer] = []

    private let storageKey =
        "isideband.reticulum.discoveredPeers"

    private init() {
        load()
    }

    func discover(
        destinationHash: String,
        displayName: String?,
        announcedHops: UInt8? = nil,
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
                announcedHops: announcedHops ?? existing.announcedHops,
                firstSeenAt: existing.firstSeenAt,
                lastSeenAt: seenAt
            )
        } else {
            peers.insert(
                ReticulumDiscoveredPeer(
                    destinationHash: cleanedHash,
                    displayName: displayName,
                    announcedHops: announcedHops,
                    firstSeenAt: seenAt,
                    lastSeenAt: seenAt
                ),
                at: 0
            )
        }

        peers.sort {
            $0.lastSeenAt > $1.lastSeenAt
        }
        persist()
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
        persist()
    }

    func clear() {
        peers.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(
            peers
        ) else {
            return
        }
        UserDefaults.standard.set(
            data,
            forKey: storageKey
        )
    }

    private func load() {
        guard let data = UserDefaults.standard.data(
                    forKey: storageKey
              ),
              let savedPeers = try? JSONDecoder().decode(
                    [ReticulumDiscoveredPeer].self,
                    from: data
              )
        else {
            return
        }
        peers = savedPeers.sorted {
            $0.lastSeenAt > $1.lastSeenAt
        }
    }
}
