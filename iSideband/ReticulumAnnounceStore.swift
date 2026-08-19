import Foundation
import Combine

@MainActor
final class ReticulumAnnounceStore: ObservableObject {
    static let shared = ReticulumAnnounceStore()

    @Published private(set) var announces: [ReticulumAnnounce] = []
    @Published private(set) var history: [ReticulumAnnounce] = []

    private let storageKey =
        "isideband.reticulum.announces"
    private var historyEventIDs = Set<Data>()

    private init() {
        load()
    }

    func save(
        _ announce: ReticulumAnnounce,
        eventID: Data
    ) {
        guard historyEventIDs.insert(eventID).inserted else {
            return
        }

        history.insert(announce, at: 0)
        if history.count > 500 {
            history.removeLast(
                history.count - 500
            )
        }

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

        privacySafeLog(
            """
            RETICULUM ANNOUNCE SAVED
            Destination: \(announce.destinationHashHex)
            Name: \(announce.displayName ?? "Unknown")
            """
        )
        persist()
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

    func ratchet(
        for destinationHash: String
    ) -> Data? {
        announce(
            for: destinationHash
        )?.ratchet
    }

    func removeAll() {
        announces.removeAll()
        history.removeAll()
        historyEventIDs.removeAll()
        persist()
    }

    private func persist() {
        let snapshot = Snapshot(
            announces: announces,
            history: history,
            historyEventIDs:
                Array(historyEventIDs)
        )
        guard let data = try? JSONEncoder().encode(
            snapshot
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
              let snapshot = try? JSONDecoder().decode(
                    Snapshot.self,
                    from: data
              )
        else {
            return
        }
        announces = snapshot.announces
        history = snapshot.history
        historyEventIDs = Set(
            snapshot.historyEventIDs
        )
    }

    private struct Snapshot: Codable {
        let announces: [ReticulumAnnounce]
        let history: [ReticulumAnnounce]
        let historyEventIDs: [Data]
    }
}
