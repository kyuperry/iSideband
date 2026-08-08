import Foundation
import Combine

@MainActor
final class LXMFManager: ObservableObject {
    static let shared = LXMFManager()

    @Published private(set) var isConnected = false
    @Published private(set) var identityReady = false
    @Published private(set) var outgoingMessages: [LXMFOutgoingMessage] = []

    private let service = LXMFService()
    private var hasStarted = false
    // Match Sideband's default 1 MB direct-delivery attachment limit.
    static let maximumAttachmentBytes = 1_000_000

    private static let storageKey = "isideband.lxmf.outgoing"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([LXMFOutgoingMessage].self, from: data) {
            outgoingMessages = saved.map { message in
                var restored = message
                if restored.status == .sending { restored.status = .queued }
                return restored
            }
        }
    }

    func start(
        bluetooth: BluetoothManager
    ) {
        // CoreBluetooth can relaunch the app directly into state restoration,
        // before a SwiftUI view task runs. Always give the native bridge the
        // current radio, but only start the queue/service once.
        ReticulumCoreBridge.shared.start(
            bluetooth: bluetooth
        )

        guard !hasStarted else {
            return
        }
        hasStarted = true

        ReticulumDecoderSelfTest.run()
        ReticulumCompatibilitySelfTest.run()
        print("Starting LXMF Manager")

        isConnected = true
        identityReady = true

        service.start(
            manager: self,
            bluetooth: bluetooth
        )
        service.processQueue()
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

    @discardableResult
    func sendAttachment(
        at fileURL: URL,
        name: String,
        mimeType: String,
        type: LXMFOutgoingAttachmentType,
        caption: String = "",
        to peer: LXMFPeer
    ) -> LXMFOutgoingMessage? {
        guard peer.isDestinationValid else {
            print("ATTACHMENT QUEUE FAILED: invalid destination")
            return nil
        }

        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            print(
                "ATTACHMENT QUEUE FAILED: file missing at \(fileURL.path)"
            )
            return nil
        }

        guard let attributes =
                try? FileManager.default.attributesOfItem(
                    atPath: fileURL.path
                ),
              let byteCount =
                attributes[.size] as? NSNumber
        else {
            print("ATTACHMENT QUEUE FAILED: could not read file size")
            return nil
        }

        print(
            """
            ATTACHMENT QUEUE CHECK
            File: \(fileURL.path)
            Size: \(byteCount.intValue) bytes
            Maximum: \(Self.maximumAttachmentBytes) bytes
            """
        )

        guard byteCount.intValue <=
                Self.maximumAttachmentBytes
        else {
            print(
                "ATTACHMENT QUEUE FAILED: attachment exceeds maximum size"
            )
            return nil
        }
        let message = LXMFOutgoingMessage(
            text: caption,
            peer: peer,
            status: .queued,
            attachment: LXMFOutgoingAttachment(
                path: fileURL.lastPathComponent,
                name: name,
                mimeType: mimeType,
                type: type
            )
        )
        outgoingMessages.append(message)
        persistQueue()
        service.processQueue()
        return message
    }
    func announceIdentity() {
        if !ReticulumCoreBridge.shared.announce() {
            service.announceIdentity()
        }
    }

    func nextQueuedMessage() -> LXMFOutgoingMessage? {
        outgoingMessages.first {
            $0.status == .queued
        }
    }

    @discardableResult
    func resendMessage(id: UUID) -> Bool {
        guard let index = outgoingMessages.firstIndex(
            where: { $0.id == id && $0.status == .failed }
        ) else {
            return false
        }

        if let attachment = outgoingMessages[index].attachment {
            let attachmentURL = attachment.resolvedFileURL()
            guard FileManager.default.fileExists(
                atPath: attachmentURL.path
            ),
            let attributes = try? FileManager.default
                .attributesOfItem(atPath: attachmentURL.path),
            let byteCount = (
                attributes[.size] as? NSNumber
            )?.intValue,
            byteCount > 0,
            byteCount <= Self.maximumAttachmentBytes else {
                return false
            }
        }

        outgoingMessages[index].status = .queued
        persistQueue()
        service.processQueue()
        return true
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
        persistQueue()

        print(
            "LXMF message \(id) status changed to \(status.rawValue)"
        )
    }

    private func persistQueue() {
        guard let data = try? JSONEncoder().encode(outgoingMessages) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

enum LXMFOutgoingAttachmentType: String, Codable, Hashable {
    case photo
    case file
    case voiceNote
}

struct LXMFOutgoingAttachment: Codable, Hashable {
    let path: String
    let name: String
    let mimeType: String
    let type: LXMFOutgoingAttachmentType

    func resolvedFileURL(
        fileManager: FileManager = .default
    ) -> URL {
        let storedURL: URL
        if path.hasPrefix("file://"),
           let parsedURL = URL(string: path) {
            storedURL = parsedURL
        } else {
            storedURL = URL(fileURLWithPath: path)
        }

        if fileManager.fileExists(atPath: storedURL.path) {
            return storedURL
        }

        guard let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return storedURL
        }

        return documentsDirectory
            .appendingPathComponent(
                "DirectAttachments",
                isDirectory: true
            )
            .appendingPathComponent(storedURL.lastPathComponent)
    }
}

struct LXMFOutgoingMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let peer: LXMFPeer
    let createdAt: Date
    var status: LXMFOutgoingStatus
    let attachment: LXMFOutgoingAttachment?

    init(
        id: UUID = UUID(),
        text: String,
        peer: LXMFPeer,
        createdAt: Date = Date(),
        status: LXMFOutgoingStatus,
        attachment: LXMFOutgoingAttachment? = nil
    ) {
        self.id = id
        self.text = text
        self.peer = peer
        self.createdAt = createdAt
        self.status = status
        self.attachment = attachment
    }
}

enum LXMFOutgoingStatus: String, Codable, Hashable {
    case queued
    case sending
    case sent
    case delivered
    case failed
}
