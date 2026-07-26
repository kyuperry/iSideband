import Foundation
import Combine

enum LXMFAnnounceType {
    case direct
    case group

    var destinationName: String {
        switch self {
        case .direct:
            return "lxmf.delivery"

        case .group:
            return "lxmf.group"
        }
    }

    var successMessage: String {
        switch self {
        case .direct:
            return "Direct message announcement sent"

        case .group:
            return "Group message announcement sent"
        }
    }

    var logName: String {
        switch self {
        case .direct:
            return "DIRECT"

        case .group:
            return "GROUP"
        }
    }
}

@MainActor
final class LXMFService: ObservableObject {
    @Published private(set) var isReady = false

    @Published private(set) var statusMessage =
        "LXMF engine not initialized"

    private weak var manager: LXMFManager?
    private weak var bluetooth: BluetoothManager?

    private var isProcessingQueue = false

    private let announceEncoder =
        ReticulumAnnounceEncoder()

    private let packetEncoder =
        ReticulumPacketEncoder()

    func start(
        manager: LXMFManager,
        bluetooth: BluetoothManager
    ) {
        self.manager = manager
        self.bluetooth = bluetooth

        isReady = true
        statusMessage = "LXMF service ready"

        print("LXMF Service started")
    }

    func stop() {
        isReady = false
        isProcessingQueue = false
        statusMessage = "LXMF service stopped"

        print("LXMF Service stopped")
    }

    func announceIdentity() {
        guard isReady else {
            statusMessage =
                "Cannot announce: LXMF service is not ready"

            print(statusMessage)
            return
        }

        guard let bluetooth else {
            statusMessage =
                "Cannot announce: RNode is unavailable"

            print(statusMessage)
            return
        }

        do {
            let identity =
                try ReticulumIdentityStore.shared
                    .loadOrCreateIdentity()

            let encodedAnnounce =
                try announceEncoder.encode(
                    identity: identity,
                    destinationName: "lxmf.delivery"
                )

            let packet =
                try packetEncoder.encodeAnnouncePacket(
                    destinationHash:
                        encodedAnnounce.destinationHash,
                    payload:
                        encodedAnnounce.payload
                )

            bluetooth.sendRadioPayload(packet)

            let destinationHex =
                encodedAnnounce.destinationHash
                    .map {
                        String(
                            format: "%02x",
                            $0
                        )
                    }
                    .joined()

            statusMessage =
                "Reticulum identity announced"

            print(
                """
                RETICULUM ANNOUNCE TRANSMITTED
                Destination name: lxmf.delivery
                Destination: \(destinationHex)
                Packet bytes: \(packet.count)
                """
            )
        } catch {
            statusMessage =
                "Announce failed: \(error.localizedDescription)"

            print(
                "RETICULUM ANNOUNCE FAILED:",
                error.localizedDescription
            )
        }
    }
    func processQueue() {
        guard isReady else {
            print(
                "LXMF queue blocked: service is not ready"
            )
            return
        }

        guard !isProcessingQueue else {
            return
        }

        guard let message =
            manager?.nextQueuedMessage()
        else {
            return
        }

        isProcessingQueue = true

        Task {
            await transmitMessage(
                of: message
            )

            isProcessingQueue = false
            processQueue()
        }
    }

    private func transmitMessage(
        of message: LXMFOutgoingMessage
    ) async {
        manager?.updateMessageStatus(
            id: message.id,
            status: .sending
        )

        guard let bluetooth else {
            manager?.updateMessageStatus(
                id: message.id,
                status: .failed
            )

            statusMessage =
                "Message failed: RNode unavailable"

            return
        }

        bluetooth.sendMessage(
            message.text
        )

        statusMessage =
            "Sending message to \(message.peer.displayName)"

        try? await Task.sleep(
            for: .seconds(1)
        )

        manager?.updateMessageStatus(
            id: message.id,
            status: .sent
        )

        statusMessage =
            "Message sent to \(message.peer.displayName)"

        print(
            """
            RADIO TRANSMISSION HANDED TO RNODE
            Destination: \(message.peer.destinationHash)
            Message: \(message.text)
            """
        )
    }
}
