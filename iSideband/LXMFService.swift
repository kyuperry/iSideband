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
    private var retryTask: Task<Void, Never>?

    private let announceEncoder =
        ReticulumAnnounceEncoder()

    private let packetEncoder =
        ReticulumPacketEncoder()

    private let lxmfMessageCodec =
        LXMFMessageCodec()

    func start(
        manager: LXMFManager,
        bluetooth: BluetoothManager
    ) {
        self.manager = manager
        self.bluetooth = bluetooth

        isReady = true
        statusMessage = "LXMF service ready"

        privacySafeLog("LXMF Service started")
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        isReady = false
        isProcessingQueue = false
        statusMessage = "LXMF service stopped"

        privacySafeLog("LXMF Service stopped")
    }

    func announceIdentity() {
        guard isReady else {
            statusMessage =
                "Cannot announce: LXMF service is not ready"

            privacySafeLog(statusMessage)
            return
        }

        guard let bluetooth else {
            statusMessage =
                "Cannot announce: RNode is unavailable"

            privacySafeLog(statusMessage)
            return
        }

        do {
            let identity =
                try ReticulumIdentityStore.shared
                    .loadOrCreateIdentity()

            let announceAppData =
                lxmfMessageCodec.encodeAnnounceAppData(
                    displayName: "iSideband"
                )

            let encodedAnnounce =
                try announceEncoder.encode(
                    identity: identity,
                    destinationName: "lxmf.delivery",
                    ratchet:
                        ReticulumRatchet.shared.publicKey,
                    appData: announceAppData
                )

            let packet =
                try packetEncoder.encodeAnnouncePacket(
                    destinationHash:
                        encodedAnnounce.destinationHash,
                    payload:
                        encodedAnnounce.payload,
                    contextFlag:
                        encodedAnnounce.containsRatchet
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

            privacySafeLog(
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

            privacySafeLog(
                "RETICULUM ANNOUNCE FAILED:",
                error.localizedDescription
            )
        }
    }
    func processQueue() {
        retryTask?.cancel()
        retryTask = nil
        guard isReady else {
            privacySafeLog(
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
            scheduleNextRetry()
            return
        }

        guard packetInterfaceReady else {
            manager?.markWaitingForInterface(id: message.id)
            scheduleQueueCheck(after: 5)
            statusMessage = "Waiting for the selected interface"
            return
        }

        isProcessingQueue = true

        Task {
            await transmitMessage(
                of: message
            )

            let awaitingAttachment = manager?
                .isAwaitingAttachmentCompletion(id: message.id) == true
            isProcessingQueue = false
            if !awaitingAttachment {
                processQueue()
            }
        }
    }

    private func transmitMessage(
        of message: LXMFOutgoingMessage
    ) async {
        
        privacySafeLog("========== TRANSMIT MESSAGE ==========")
        privacySafeLog("Attachment present: \(message.attachment != nil)")
        privacySafeLog("Text: \(message.text)")
        manager?.markAttemptStarted(id: message.id)

        guard let bluetooth else {
            manager?.recordTransientFailure(
                id: message.id,
                reason: "Bluetooth manager unavailable"
            )

            statusMessage =
                "Message failed: RNode unavailable"

            return
        }

        if let attachment = message.attachment {
            let attachmentURL = attachment.resolvedFileURL()

            privacySafeLog(
                """
                LXMF ATTACHMENT REQUEST
                Stored path: \(attachment.path)
                Resolved path: \(attachmentURL.path)
                Exists: \(FileManager.default.fileExists(
                    atPath: attachmentURL.path
                ))
                Name: \(attachment.name)
                MIME: \(attachment.mimeType)
                """
            )

            let accepted = await
                ReticulumCoreBridge.shared.sendAttachmentAsync(
                    at: attachmentURL,
                    name: attachment.name,
                    mimeType: attachment.mimeType,
                    caption: message.text,
                    destinationHash:
                        message.peer.destinationHash,
                    clientID: message.id
                )

            if !accepted {
                manager?.recordTransientFailure(
                    id: message.id,
                    reason: "Reticulum rejected the attachment handoff"
                )

                statusMessage =
                    "Attachment handoff failed; retry scheduled"
            }

            return
        }

        if await ReticulumCoreBridge.shared.sendAsync(
            text: message.text,
            destinationHash:
                message.peer.destinationHash,
            clientID: message.id,
            direct: manager?.prefersDirectDelivery(
                to: message.peer
            ) ?? false
        ) {
            statusMessage =
                "Message handed to Reticulum delivery"
            return
        }

        guard PacketInterfaceManager.shared
            .isActive(.bluetoothRNode) else {
            manager?.recordTransientFailure(
                id: message.id,
                reason: "Reticulum TCP handoff failed"
            )
            statusMessage =
                "Message queued for another Raspberry Pi attempt"
            return
        }

        do {
            let destinationHash =
                try packetEncoder.destinationHashData(
                    from:
                        message.peer.destinationHash
                )
            guard let destinationPublicKey =
                    ReticulumAnnounceStore.shared
                        .publicKey(
                            for:
                                message.peer
                                    .destinationHash
                        )
            else {
                throw LXMFMessageCodecError.unknownSource
            }

            let identity =
                try ReticulumIdentityStore.shared
                    .loadOrCreateIdentity()
            let sourceHash =
                try announceEncoder.destinationHash(
                    identity: identity,
                    destinationName: "lxmf.delivery"
                )
            let lxmfPayload =
                try LXMFMessageCodec().encode(
                    content: message.text,
                    destinationHash:
                        destinationHash,
                    sourceHash: sourceHash,
                    sourceIdentity: identity
                )
            let encryptedPayload =
                try identity.encrypt(
                    Data(
                        lxmfPayload.dropFirst(
                            ReticulumPacketEncoder
                                .destinationHashByteCount
                        )
                    ),
                    for: destinationPublicKey,
                    ratchet:
                        ReticulumAnnounceStore.shared
                            .ratchet(
                                for:
                                    message.peer
                                        .destinationHash
                            )
                )
            let packet =
                try packetEncoder.encodeDataPacket(
                    destinationHash:
                        destinationHash,
                    encryptedPayload:
                        encryptedPayload
                )

            bluetooth.sendRadioPayload(packet)
            manager?.updateMessageStatus(
                id: message.id,
                status: .sent
            )
            statusMessage =
                "Message sent to \(message.peer.displayName)"

            privacySafeLog(
                """
                LXMF PACKET HANDED TO RNODE
                Destination: \(message.peer.destinationHash)
                Packet bytes: \(packet.count)
                """
            )
        } catch {
            manager?.updateMessageStatus(
                id: message.id,
                status: .failed
            )
            statusMessage =
                "Message failed: \(error.localizedDescription)"
            privacySafeLog(statusMessage)
        }
    }

    private var packetInterfaceReady: Bool {
        switch PacketInterfaceManager.shared.activeInterface {
        case .none:
            return false
        case .bluetoothRNode:
            return bluetooth?.radioReady == true
        case .raspberryPi:
            return PiHaLowInterfaceManager.shared.state == .connected
        }
    }

    private func scheduleNextRetry() {
        guard let retryDate = manager?.nextRetryDate else { return }
        scheduleQueueCheck(
            after: max(retryDate.timeIntervalSinceNow, 0.25)
        )
    }

    private func scheduleQueueCheck(after delay: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(
                for: .seconds(max(delay, 0.25))
            )
            guard !Task.isCancelled else { return }
            self?.processQueue()
        }
    }
}
