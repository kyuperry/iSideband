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
    private var persistenceTask: Task<Void, Never>?
    // Match Sideband's default 1 MB direct-delivery attachment limit.
    static let maximumAttachmentBytes = 1_000_000

    private static let storageKey = "isideband.lxmf.outgoing"

    private init() {
        let legacyData = UserDefaults.standard.data(forKey: Self.storageKey)
        let storedData = MessageDatabase.shared.data(forKey: Self.storageKey)
            ?? legacyData
        if let data = storedData,
           let saved = try? JSONDecoder().decode([LXMFOutgoingMessage].self, from: data) {
            outgoingMessages = saved.map { message in
                var restored = message
                if restored.status == .sending ||
                    restored.status == .waitingForInterface {
                    restored.status = .queued
                }
                return restored
            }
            let normalizedData = try? JSONEncoder().encode(outgoingMessages)
            if let normalizedData,
               MessageDatabase.shared.set(
                normalizedData,
                forKey: Self.storageKey
               ) {
                UserDefaults.standard.removeObject(forKey: Self.storageKey)
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
        privacySafeLog("Starting LXMF Manager")

        isConnected = true
        identityReady = true

        service.start(
            manager: self,
            bluetooth: bluetooth
        )
        service.processQueue()
    }

    func stop() {
        privacySafeLog("Stopping LXMF Manager")

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
            privacySafeLog("Cannot send an empty LXMF message")
            return nil
        }

        guard peer.isDestinationValid else {
            privacySafeLog("Invalid LXMF destination")
            return nil
        }

        let message = LXMFOutgoingMessage(
            text: trimmedText,
            peer: peer,
            status: .queued
        )

        outgoingMessages.append(message)
        persistQueue()

        privacySafeLog(
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
            privacySafeLog("ATTACHMENT QUEUE FAILED: invalid destination")
            return nil
        }

        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            privacySafeLog(
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
            privacySafeLog("ATTACHMENT QUEUE FAILED: could not read file size")
            return nil
        }

        privacySafeLog(
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
            privacySafeLog(
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
        outgoingMessages
            .filter {
                $0.status == .queued ||
                $0.status == .waitingForInterface ||
                ($0.status == .retryScheduled &&
                 ($0.nextRetryAt ?? .distantPast) <= Date())
            }
            .min { lhs, rhs in
                let leftPriority = lhs.attachment == nil ? 0 : 1
                let rightPriority = rhs.attachment == nil ? 0 : 1
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func prefersDirectDelivery(to peer: LXMFPeer) -> Bool {
        guard let announce = ReticulumAnnounceStore.shared.announce(
            for: peer.destinationHash
        ),
        Date().timeIntervalSince(announce.receivedAt) < 10 * 60 else {
            return false
        }
        return outgoingMessages.contains {
            $0.peer.destinationHash == peer.destinationHash &&
            ($0.status == .sent || $0.status == .delivered) &&
            Date().timeIntervalSince($0.createdAt) < 2 * 60
        }
    }

    var hasActiveMessageTraffic: Bool {
        outgoingMessages.contains {
            $0.status == .sending
        }
    }

    func isAwaitingAttachmentCompletion(id: UUID) -> Bool {
        outgoingMessages.contains {
            $0.id == id &&
            $0.attachment != nil &&
            $0.status == .sending
        }
    }

    var nextRetryDate: Date? {
        outgoingMessages
            .filter { $0.status == .retryScheduled }
            .compactMap(\.nextRetryAt)
            .min()
    }

    func markWaitingForInterface(id: UUID) {
        updateMessageStatus(id: id, status: .waitingForInterface)
    }

    func markAttemptStarted(id: UUID) {
        guard let index = outgoingMessages.firstIndex(
            where: { $0.id == id }
        ) else { return }
        outgoingMessages[index].attemptCount =
            (outgoingMessages[index].attemptCount ?? 0) + 1
        outgoingMessages[index].nextRetryAt = nil
        outgoingMessages[index].lastError = nil
        outgoingMessages[index].status = .sending
        if outgoingMessages[index].attachment != nil {
            outgoingMessages[index].transmissionStartedAt = Date()
        }
        persistQueue()
    }

    func recordTransientFailure(id: UUID, reason: String) {
        guard let index = outgoingMessages.firstIndex(
            where: { $0.id == id }
        ) else { return }
        let attempts = outgoingMessages[index].attemptCount ?? 1
        outgoingMessages[index].lastError = reason
        outgoingMessages[index].transmissionStartedAt = nil
        if attempts >= 5 {
            outgoingMessages[index].status = .failed
            outgoingMessages[index].nextRetryAt = nil
        } else {
            let delay = min(
                pow(2.0, Double(max(attempts - 1, 0))) * 5,
                120
            )
            outgoingMessages[index].status = .retryScheduled
            outgoingMessages[index].nextRetryAt = Date()
                .addingTimeInterval(
                    delay + Double.random(in: 0...2)
                )
        }
        persistQueue()
        service.processQueue()
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
        outgoingMessages[index].transmissionStartedAt = nil
        outgoingMessages[index].attemptCount = 0
        outgoingMessages[index].nextRetryAt = nil
        outgoingMessages[index].lastError = nil
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
        if status == .sending,
           outgoingMessages[index].attachment != nil,
           outgoingMessages[index].transmissionStartedAt == nil {
            outgoingMessages[index].transmissionStartedAt = Date()
        } else if status == .queued {
            outgoingMessages[index].transmissionStartedAt = nil
        }
        if status == .sent || status == .delivered {
            outgoingMessages[index].nextRetryAt = nil
            outgoingMessages[index].lastError = nil
        }
        scheduleQueuePersistence()

        if status == .sent || status == .delivered || status == .failed {
            service.processQueue()
        }

        privacySafeLog(
            "LXMF message \(id) status changed to \(status.rawValue)"
        )
    }

    private func persistQueue() {
        guard let data = try? JSONEncoder().encode(outgoingMessages) else { return }
        if !MessageDatabase.shared.set(data, forKey: Self.storageKey) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func scheduleQueuePersistence() {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.persistQueue()
        }
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
    var transmissionStartedAt: Date?
    let attachment: LXMFOutgoingAttachment?
    var attemptCount: Int?
    var nextRetryAt: Date?
    var lastError: String?

    init(
        id: UUID = UUID(),
        text: String,
        peer: LXMFPeer,
        createdAt: Date = Date(),
        status: LXMFOutgoingStatus,
        transmissionStartedAt: Date? = nil,
        attachment: LXMFOutgoingAttachment? = nil,
        attemptCount: Int? = 0,
        nextRetryAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.text = text
        self.peer = peer
        self.createdAt = createdAt
        self.status = status
        self.transmissionStartedAt = transmissionStartedAt
        self.attachment = attachment
        self.attemptCount = attemptCount
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
    }
}

enum LXMFOutgoingStatus: String, Codable, Hashable {
    case queued
    case waitingForInterface
    case retryScheduled
    case sending
    case sent
    case delivered
    case failed
}
