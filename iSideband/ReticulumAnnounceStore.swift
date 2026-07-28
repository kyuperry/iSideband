import Foundation
import Combine

@MainActor
final class ReticulumAnnounceStore: ObservableObject {
    static let shared = ReticulumAnnounceStore()

    @Published private(set) var announces: [ReticulumAnnounce] = []
    @Published private(set) var history: [ReticulumAnnounce] = []

    private init() {}

    func save(
        _ announce: ReticulumAnnounce,
        eventID: Data
    ) {
        guard historyEventIDs.insert(eventID).inserted else {
            return
        }

        history.insert(announce, at: 0)

        if let existingIndex = announces.firstIndex(
            where: {
                $0.destinationHash ==
                    announce.destinationHash
            }
        ) {
            announces[existingIndex] = announce
        } else {
            announces.append(announce)
        }

        announces.sort {
            $0.receivedAt > $1.receivedAt
        }

        print(
            """
            RETICULUM ANNOUNCE SAVED
            Destination: \(announce.destinationHashHex)
            Name: \(announce.displayName ?? "Unknown")
            """
        )
    }

    func announce(
        for destinationHash: String
    ) -> ReticulumAnnounce? {
        let cleanedHash = destinationHash
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        return announces.first {
            $0.destinationHashHex == cleanedHash
        }
    }

    func publicKey(
        for destinationHash: String
    ) -> Data? {
        announce(
            for: destinationHash
        )?.publicKey
    }

    func removeAll() {
        announces.removeAll()
        history.removeAll()
        historyEventIDs.removeAll()
    }

    private var historyEventIDs = Set<Data>()
}
