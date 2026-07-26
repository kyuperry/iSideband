import Foundation
import Combine

@MainActor
final class LXMFManager: ObservableObject {
    static let shared = LXMFManager()

    @Published private(set) var isConnected = false
    @Published private(set) var identityReady = false
    @Published private(set) var outgoingMessages: [LXMFOutgoingMessage] = []

    private let service = LXMFService()

    private init() { }

    func start() {
        print("Starting LXMF Manager")

        isConnected = true
        identityReady = true

        service.start(manager: self)
    }

    func stop() {
        print("Stopping LXMF Manager")

        service.stop()

        isConnected = false
        identityReady = false
    }

    @discardableResult
    func send(
        text: String,
        to peer: LXMFPeer
    ) -> LXMFOutgoingMessage? {
        let trimmedText = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedText.isEmpty else {
            print("Cannot send an empty LXMF message")
            return nil
        }

        guard peer.isDestinationValid else {
            print("Invalid LXMF destination")
            return nil
        }

        let message = LXMFOutgoingMessage(
            text: trimmedText,
            peer: peer,
            status: .queued
        )

        outgoingMessages.append(message)

        print(
            """
            LXMF SEND
            Peer: \(peer.displayName)
            Destination: \(peer.destinationHash)
            Message: \(trimmedText)
            Status: \(message.status.rawValue)
            """
        )

        service.processQueue()

        return message
    }

    func nextQueuedMessage() -> LXMFOutgoingMessage? {
        outgoingMessages.first {
            $0.status == .queued
        }
    }

    func updateMessageStatus(
        id: UUID,
        status: LXMFOutgoingStatus
    ) {
        guard let index = outgoingMessages.firstIndex(
            where: { $0.id == id }
        ) else {
            return
        }

        outgoingMessages[index].status = status

        print(
            "LXMF message \(id) status changed to \(status.rawValue)"
        )
    }
}

struct LXMFOutgoingMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let peer: LXMFPeer
    let createdAt: Date
    var status: LXMFOutgoingStatus

    init(
        id: UUID = UUID(),
        text: String,
        peer: LXMFPeer,
        createdAt: Date = Date(),
        status: LXMFOutgoingStatus
    ) {
        self.id = id
        self.text = text
        self.peer = peer
        self.createdAt = createdAt
        self.status = status
    }
}

enum LXMFOutgoingStatus: String, Codable, Hashable {
    case queued
    case sending
    case sent
    case delivered
    case failed
}
