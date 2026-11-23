import Foundation
import Combine

@MainActor
final class ReticulumAnnounceStore: ObservableObject {
    static let shared = ReticulumAnnounceStore()

    @Published private(set) var announces: [ReticulumAnnounce] = []
    @Published private(set) var history: [ReticulumAnnounce] = []

    struct ListEntry: Identifiable {
        let destinationHash: String
        let identityHash: String?
        var displayName: String?
        let receivedAt: Date

        var id: String { identityHash ?? destinationHash }
    }

    @Published private var nativeAnnounces: [String: ListEntry] = [:]

    var listEntries: [ListEntry] {
        let packetEntries = announces.map {
            ListEntry(
                destinationHash: $0.destinationHashHex,
                identityHash: $0.identityHashHex,
                displayName: $0.displayName,
                receivedAt: $0.receivedAt
            )
        }
        let identitiesByDestination = Dictionary(
            announces.map { ($0.destinationHashHex, $0.identityHashHex) },
            uniquingKeysWith: { latest, _ in latest }
        )
        let nativeEntries = nativeAnnounces.values.map {
            ListEntry(
                destinationHash: $0.destinationHash,
                identityHash: $0.identityHash ?? identitiesByDestination[$0.destinationHash],
                displayName: $0.displayName,
                receivedAt: $0.receivedAt
            )
        }
        let newestFirst = (packetEntries + nativeEntries).sorted {
            $0.receivedAt > $1.receivedAt
        }
        var grouped: [String: ListEntry] = [:]
        for entry in newestFirst {
            if var newer = grouped[entry.id] {
                newer.displayName = newer.displayName ?? entry.displayName
                grouped[entry.id] = newer
            } else {
                grouped[entry.id] = entry
            }
        }
        return grouped.values.sorted {
            if $0.receivedAt == $1.receivedAt { return $0.id < $1.id }
            return $0.receivedAt > $1.receivedAt
        }
    }

    func recordNativeAnnounce(_ entry: ListEntry) {
        nativeAnnounces[entry.destinationHash] = entry
    }

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
        nativeAnnounces.removeAll()
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
