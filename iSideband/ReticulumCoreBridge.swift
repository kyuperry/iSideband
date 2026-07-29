import CryptoKit
import Combine
import Foundation

nonisolated private func reticulumRawTransmit(
    _ userData: UnsafeMutableRawPointer?,
    _ bytes: UnsafePointer<UInt8>?,
    _ length: Int32
) {
    guard let userData, let bytes, length > 0 else {
        return
    }
    let bridge = Unmanaged<ReticulumCoreBridge>
        .fromOpaque(userData)
        .takeUnretainedValue()
    let packet = Data(
        bytes: bytes,
        count: Int(length)
    )
    Task { @MainActor in
        bridge.transmit(packet)
    }
}

nonisolated private func reticulumInboundMessage(
    _ userData: UnsafeMutableRawPointer?,
    _ source: UnsafePointer<CChar>?,
    _ title: UnsafePointer<CChar>?,
    _ content: UnsafePointer<CChar>?,
    _ timestamp: Double,
    _ messageID: UnsafePointer<CChar>?,
    _ attachmentPath: UnsafePointer<CChar>?,
    _ attachmentName: UnsafePointer<CChar>?,
    _ attachmentMIME: UnsafePointer<CChar>?,
    _ attachmentType: Int32
) {
    guard let userData, let source, let content else {
        return
    }
    let bridge = Unmanaged<ReticulumCoreBridge>
        .fromOpaque(userData)
        .takeUnretainedValue()
    let sourceHex = String(cString: source)
    let messageTitle = title.map(String.init(cString:)) ?? ""
    let messageContent = String(cString: content)
    let inboundID = messageID.map(String.init(cString:)) ?? ""
    let inboundPath = attachmentPath.map(String.init(cString:)) ?? ""
    let inboundName = attachmentName.map(String.init(cString:)) ?? ""
    let inboundMIME = attachmentMIME.map(String.init(cString:)) ?? ""
    Task { @MainActor in
        bridge.receive(
            sourceHex: sourceHex,
            title: messageTitle,
            content: messageContent,
            timestamp: timestamp,
            messageIDHex: inboundID,
            attachmentPath: inboundPath,
            attachmentName: inboundName,
            attachmentMIME: inboundMIME,
            attachmentType: attachmentType
        )
    }
}

nonisolated private func reticulumMessageStatus(
    _ userData: UnsafeMutableRawPointer?,
    _ clientID: UnsafePointer<CChar>?,
    _ status: UnsafePointer<CChar>?
) {
    guard let userData, let clientID, let status else { return }
    let bridge = Unmanaged<ReticulumCoreBridge>
        .fromOpaque(userData).takeUnretainedValue()
    let id = String(cString: clientID)
    let value = String(cString: status)
    Task { @MainActor in bridge.receiveStatus(clientID: id, status: value) }
}

nonisolated private func reticulumCoreLog(
    _ userData: UnsafeMutableRawPointer?,
    _ level: Int32,
    _ line: UnsafePointer<CChar>?
) {
    guard let userData, let line else {
        return
    }
    let bridge = Unmanaged<ReticulumCoreBridge>
        .fromOpaque(userData)
        .takeUnretainedValue()
    let message = String(cString: line)
    Task { @MainActor in
        bridge.recordLog(
            level: level,
            message: message
        )
    }
}

@MainActor
final class ReticulumCoreBridge: ObservableObject {
    static let shared = ReticulumCoreBridge()

    @Published private(set) var isRunning = false
    @Published private(set) var destinationHash = ""
    @Published private(set) var status =
        "Reticulum core not started"

    private var handle: runcore_handle_t = 0
    private weak var bluetooth: BluetoothManager?
    private var routeRefreshTimer: Timer?
    private var lastAutomaticAnnounce: Date?

    private init() {}

    func start(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        guard handle == 0 else {
            return
        }

        do {
            let root = try coreDirectory()
            let contacts = root.appendingPathComponent(
                "contacts",
                isDirectory: true
            )
            let send = root.appendingPathComponent(
                "send",
                isDirectory: true
            )
            let messages = root.appendingPathComponent(
                "messages",
                isDirectory: true
            )
            for directory in [root, contacts, send, messages] {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }

            handle = contacts.path.withCString { contactsPath in
                send.path.withCString { sendPath in
                    messages.path.withCString { messagesPath in
                        runcore_start(
                            contactsPath,
                            sendPath,
                            messagesPath,
                            4
                        )
                    }
                }
            }
            guard handle != 0 else {
                status = "Reticulum core failed to start"
                return
            }

            let context = Unmanaged
                .passUnretained(self)
                .toOpaque()
            runcore_set_log_cb(
                reticulumCoreLog,
                context
            )
            guard runcore_attach_raw_interface(
                handle,
                reticulumRawTransmit,
                context,
                5_000
            ) == 0,
            runcore_set_inbound_cb(
                handle,
                reticulumInboundMessage,
                context
            ) == 0,
            runcore_set_status_cb(
                handle,
                reticulumMessageStatus,
                context
            ) == 0 else {
                status =
                    "Reticulum RNode bridge failed to start"
                return
            }

            if let value = runcore_destination_hash_hex(
                handle
            ) {
                destinationHash = String(cString: value)
                runcore_free_string(value)
            }
            isRunning = true
            status = "Reticulum Link core ready"
            startRouteMaintenance()
        } catch {
            status =
                "Reticulum core failed: \(error.localizedDescription)"
        }
    }

    func feed(_ packet: Data) {
        guard handle != 0, !packet.isEmpty else {
            return
        }
        packet.withUnsafeBytes { rawBuffer in
            guard let baseAddress =
                    rawBuffer.bindMemory(
                        to: UInt8.self
                    ).baseAddress else {
                return
            }
            _ = runcore_raw_interface_receive(
                handle,
                baseAddress,
                Int32(packet.count)
            )
        }
    }

    func announce() -> Bool {
        guard handle != 0,
              runcore_announce(handle) == 0 else {
            return false
        }
        lastAutomaticAnnounce = Date()
        return true
    }

    func radioDataChannelReady() {
        requestAutomaticAnnounce(
            reason: "Bluetooth route advertised",
            minimumInterval: 0
        )
    }

    func send(
        text: String,
        destinationHash: String,
        direct: Bool = true
    ) -> Bool {
        guard handle != 0 else {
            return false
        }
        return destinationHash.withCString {
            destination in
            text.withCString { content in
                runcore_send_text(
                    handle,
                    destination,
                    content,
                    direct ? 1 : 0
                ) == 0
            }
        }
    }

    func sendAttachment(
        at fileURL: URL,
        name: String,
        mimeType: String,
        caption: String,
        destinationHash: String,
        clientID: UUID
    ) -> Bool {
        guard handle != 0 else { return false }
        return destinationHash.withCString { destination in
            caption.withCString { content in
                fileURL.path.withCString { path in
                    name.withCString { filename in
                        mimeType.withCString { mime in
                            clientID.uuidString.withCString { identifier in
                                runcore_send_attachment(
                                    handle, destination, content, path,
                                    filename, mime, identifier
                                ) == 0
                            }
                        }
                    }
                }
            }
        }
    }

    func receiveStatus(clientID: String, status: String) {
        guard let id = UUID(uuidString: clientID),
              let value = LXMFOutgoingStatus(rawValue: status) else { return }
        LXMFManager.shared.updateMessageStatus(id: id, status: value)
    }

    func transmit(_ packet: Data) {
        bluetooth?.sendRadioPayload(packet)
    }

    func receive(
        sourceHex: String,
        title: String,
        content: String,
        timestamp: Double,
        messageIDHex: String,
        attachmentPath: String,
        attachmentName: String,
        attachmentMIME: String,
        attachmentType: Int32
    ) {
        guard let sourceHash = Data(hex: sourceHex),
              let localHash = Data(
                hex: destinationHash
              ),
              sourceHash != localHash else {
            return
        }
        var identifierMaterial = Data()
        identifierMaterial.append(sourceHash)
        identifierMaterial.append(Data(content.utf8))
        identifierMaterial.append(withUnsafeBytes(of: timestamp.bitPattern.bigEndian) { Data($0) })
        let suppliedID = Data(hex: messageIDHex)
        let message = LXMFIncomingMessage(
            id: suppliedID ?? Data(SHA256.hash(data: identifierMaterial)),
            destinationHash: localHash,
            sourceHash: sourceHash,
            timestamp: Date(
                timeIntervalSince1970: timestamp
            ),
            title: title,
            content: content,
            attachmentPath: attachmentPath.isEmpty ? nil : attachmentPath,
            attachmentName: attachmentName.isEmpty ? nil : attachmentName,
            attachmentMIME: attachmentMIME.isEmpty ? nil : attachmentMIME,
            attachmentType: attachmentType == 1 ? .photo : (attachmentType == 2 ? .file : nil)
        )
        guard LXMFIncomingMessageStore.shared.save(message) else { return }
        let senderName = LXMFContactStore.shared.contact(for: message.sourceHashHex)?.displayName
        LXMFMessageNotificationManager.shared.notify(message: message, senderName: senderName)
        status =
            "Direct message received from \(sourceHex.prefix(8))"
        requestAutomaticAnnounce(
            reason: "Return route refreshed",
            minimumInterval: 15
        )
    }

    func recordLog(
        level: Int32,
        message: String
    ) {
        let lowered = message.lowercased()
        guard lowered.contains("link") ||
                lowered.contains("lxmf") ||
                lowered.contains("announce") ||
                lowered.contains("deliver") ||
                lowered.contains("failed") ||
                lowered.contains("error") else {
            return
        }
        status = message
        print(
            "Reticulum core [\(level)]: \(message)"
        )
    }

    private func startRouteMaintenance() {
        routeRefreshTimer?.invalidate()
        routeRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: 45,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestAutomaticAnnounce(
                    reason: "Return route refreshed",
                    minimumInterval: 40
                )
            }
        }
    }

    private func requestAutomaticAnnounce(
        reason: String,
        minimumInterval: TimeInterval
    ) {
        guard handle != 0,
              bluetooth?.connectedDeviceID != nil else {
            return
        }
        if let lastAutomaticAnnounce,
           Date().timeIntervalSince(lastAutomaticAnnounce) <
                minimumInterval {
            return
        }
        guard runcore_announce(handle) == 0 else {
            return
        }
        lastAutomaticAnnounce = Date()
        status = reason
    }

    private func coreDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent(
            "ReticulumCore",
            isDirectory: true
        )
    }
}

private extension Data {
    init?(hex: String) {
        let value = hex.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard value.count.isMultiple(of: 2) else {
            return nil
        }
        var data = Data()
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(
                value[index..<next],
                radix: 16
            ) else {
                return nil
            }
            data.append(byte)
            index = next
        }
        self = data
    }
}
