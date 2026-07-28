import Foundation

struct ReticulumAnnounceEventTracker {
    enum Decision: Equatable {
        case accepted
        case ownAnnounce
        case duplicate
    }

    private var handledEventIDs = Set<Data>()
    private var handledEventIDOrder: [Data] = []
    private let maximumRememberedEvents: Int

    init(maximumRememberedEvents: Int = 512) {
        self.maximumRememberedEvents =
            max(1, maximumRememberedEvents)
    }

    mutating func decision(
        for announce: ReticulumAnnounce,
        eventID: Data,
        localPublicKey: Data?
    ) -> Decision {
        if announce.publicKey == localPublicKey {
            return .ownAnnounce
        }

        guard handledEventIDs.insert(eventID).inserted else {
            return .duplicate
        }

        handledEventIDOrder.append(eventID)

        if handledEventIDOrder.count >
            maximumRememberedEvents {
            let expiredID = handledEventIDOrder.removeFirst()
            handledEventIDs.remove(expiredID)
        }

        return .accepted
    }
}
