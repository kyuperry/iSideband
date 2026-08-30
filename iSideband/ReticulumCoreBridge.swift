import CryptoKit
import Combine
import Foundation
import AVFoundation
import CoreLocation

enum AutomaticAnnouncePreferenceKey {
    static let enabled =
        "isideband.reticulum.autoAnnounce.enabled"
    static let intervalMinutes =
        "isideband.reticulum.autoAnnounce.intervalMinutes"
    static let lastAnnouncedAt =
        "isideband.reticulum.autoAnnounce.lastAnnouncedAt"
}

enum TelemetryPreferenceKey {
    static let shareTimestamp =
        "isideband.telemetry.shareTimestamp"
    static let shareLocation =
        "shareLocationOnMesh"
}

enum LXSTCallStatus: Int32, Equatable {
    case busy = 0
    case rejected = 1
    case calling = 2
    case available = 3
    case ringing = 4
    case connecting = 5
    case established = 6
}

struct RemoteNodeLocation: Identifiable, Hashable, Codable {
    let sourceHash: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let telemetryDate: Date?
    let receivedAt: Date

    var id: String { sourceHash }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}

enum AutomaticAnnounceInterval:
    Int,
    CaseIterable,
    Identifiable
{
    case tenMinutes = 10
    case thirtyMinutes = 30
    case oneHour = 60
    case threeHours = 180
    case sixHours = 360
    case twelveHours = 720
    case twentyFourHours = 1_440

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tenMinutes: "10 Minutes"
        case .thirtyMinutes: "30 Minutes"
        case .oneHour: "1 Hour"
        case .threeHours: "3 Hours"
        case .sixHours: "6 Hours"
        case .twelveHours: "12 Hours"
        case .twentyFourHours: "24 Hours"
        }
    }

    var timeInterval: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}

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
    _ attachmentType: Int32,
    _ hasLocation: Int32,
    _ latitude: Double,
    _ longitude: Double,
    _ accuracy: Double,
    _ locationTimestamp: Int64
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
            attachmentType: attachmentType,
            location: hasLocation != 0
                ? RemoteNodeLocation(
                    sourceHash: sourceHex,
                    latitude: latitude,
                    longitude: longitude,
                    accuracy: accuracy,
                    telemetryDate: locationTimestamp > 0
                        ? Date(
                            timeIntervalSince1970:
                                TimeInterval(locationTimestamp)
                        )
                        : nil,
                    receivedAt: Date()
                )
                : nil
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

nonisolated private func reticulumLXSTState(
    _ userData: UnsafeMutableRawPointer?,
    _ status: Int32,
    _ remoteIdentityHash: UnsafePointer<CChar>?
) {
    guard let userData,
          let callStatus = LXSTCallStatus(rawValue: status) else { return }
    let bridge = Unmanaged<ReticulumCoreBridge>
        .fromOpaque(userData).takeUnretainedValue()
    let remoteHash = remoteIdentityHash.map(String.init(cString:)) ?? ""
    Task { @MainActor in
        bridge.receiveLXSTState(callStatus, remoteIdentityHash: remoteHash)
    }
}

nonisolated private func reticulumLXSTFrame(
    _ userData: UnsafeMutableRawPointer?,
    _ codec: Int32,
    _ bytes: UnsafePointer<UInt8>?,
    _ length: Int32
) {
    guard let userData, let bytes, length > 0 else { return }
    let bridge = Unmanaged<ReticulumCoreBridge>
        .fromOpaque(userData).takeUnretainedValue()
    let frame = Data(bytes: bytes, count: Int(length))
    Task { @MainActor in bridge.receiveLXSTFrame(codec: codec, data: frame) }
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
    private static let maximumStoredRemoteNodes = 256
    static let remoteNodeStaleInterval: TimeInterval =
        24 * 60 * 60

    @Published private(set) var isRunning = false
    @Published private(set) var destinationHash = ""
    @Published private(set) var status =
        "Reticulum core not started"
    @Published private(set) var lxstCallStatus: LXSTCallStatus = .available
    @Published private(set) var lxstRemoteIdentityHash = ""
    @Published private(set) var lxstAudioStatus = "Audio inactive"
    @Published private(set) var remoteNodeLocations:
        [String: RemoteNodeLocation] = [:]

    private var handle: runcore_handle_t = 0
    private let inboundPacketQueue = DispatchQueue(
        label: "com.kyleperry.iSideband.reticulum.inbound",
        qos: .userInitiated
    )
    private let outboundCoreQueue = DispatchQueue(
        label: "com.kyleperry.iSideband.reticulum.outbound",
        qos: .userInitiated
    )
    private weak var bluetooth: BluetoothManager?
    private var routeRefreshTimer: Timer?
    private var appIsActive = true
    private var lastAutomaticAnnounce: Date?
    var lxstFrameHandler: ((Int32, Data) -> Void)?
    private lazy var lxstAudioEngine = LXSTAudioEngine(
        frameSender: { [weak self] frame in
            self?.sendLXSTOpusFrame(frame)
        },
        statusHandler: { [weak self] status in
            Task { @MainActor in
                self?.lxstAudioStatus = status
            }
        }
    )
    private let remoteNodeLocationsStorageKey =
        "isideband.reticulum.remoteNodeLocations"

    private init() {
        UserDefaults.standard.register(
            defaults: [
                TelemetryPreferenceKey.shareTimestamp: true,
                TelemetryPreferenceKey.shareLocation: false,
                AutomaticAnnouncePreferenceKey.enabled:
                    false,
                AutomaticAnnouncePreferenceKey
                    .intervalMinutes:
                    AutomaticAnnounceInterval
                        .thirtyMinutes.rawValue
            ]
        )
        lastAutomaticAnnounce =
            UserDefaults.standard.object(
                forKey: AutomaticAnnouncePreferenceKey
                    .lastAnnouncedAt
            ) as? Date
        loadRemoteNodeLocations()
    }

    func ingestPaperMessageURI(_ uri: String) -> String {
        guard handle != 0 else {
            return "The Reticulum core is not ready yet."
        }
        let result = uri.withCString {
            runcore_ingest_lxm_uri(handle, $0)
        }
        switch result {
        case 0:
            return "Message decrypted and added to your conversations."
        case 1:
            return "This paper message has already been scanned."
        case 2:
            return "This paper message is addressed to a different LXMF identity."
        default:
            return "The QR code is not a valid LXMF paper message."
        }
    }

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
                bluetooth.estimatedRadioBitrate
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
            ) == 0,
            runcore_lxst_set_callbacks(
                handle,
                reticulumLXSTState,
                reticulumLXSTFrame,
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
            applySavedTelemetryPreferences()
            synchronizeActivePacketInterface()
            startRouteMaintenance()
        } catch {
            status =
                "Reticulum core failed: \(error.localizedDescription)"
        }
    }

    func synchronizeActivePacketInterface() {
        guard handle != 0 else { return }
        let useBluetooth = PacketInterfaceManager.shared
            .isActive(.bluetoothRNode)
        let useWiFiLAN = PacketInterfaceManager.shared
            .isActive(.wifiLocalNetwork)
        let useRaspberryPi = PacketInterfaceManager.shared
            .isActive(.raspberryPi)
        let activeHandle = handle
        outboundCoreQueue.async {
            _ = runcore_set_raw_interface_enabled(
                activeHandle,
                useBluetooth ? 1 : 0
            )
            if !useWiFiLAN {
                _ = runcore_disconnect_tcp_interface(activeHandle)
            }
            if !useRaspberryPi {
                _ = runcore_disconnect_raspberry_pi_interface(activeHandle)
            }
        }
    }

    func placeLXSTCall(
        destinationHash: String,
        profile: Int32 = 0x40
    ) async -> Bool {
        guard handle != 0 else { return false }
        let activeHandle = handle
        return await withCheckedContinuation { continuation in
            outboundCoreQueue.async {
                let succeeded = destinationHash.withCString {
                    runcore_lxst_call(activeHandle, $0, profile) == 0
                }
                continuation.resume(returning: succeeded)
            }
        }
    }

    func answerLXSTCall() -> Bool {
        handle != 0 && runcore_lxst_answer(handle) == 0
    }

    func hangupLXSTCall(reject: Bool = false) {
        guard handle != 0 else { return }
        _ = runcore_lxst_hangup(handle, reject ? 1 : 0)
    }

    func setLXSTSpeakerphone(_ enabled: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            try session.overrideOutputAudioPort(enabled ? .speaker : .none)
        } catch {
            privacySafeLog("LXST audio route change failed", error.localizedDescription)
        }
    }

    func setLXSTMicrophoneMuted(_ muted: Bool) {
        lxstAudioEngine.setMuted(muted)
    }

    private nonisolated func sendLXSTOpusFrame(_ frame: Data) {
        Task { @MainActor [weak self] in
            guard let self, self.handle != 0 else { return }
            let activeHandle = self.handle
            self.outboundCoreQueue.async {
                frame.withUnsafeBytes { bytes in
                    guard let baseAddress = bytes.bindMemory(
                        to: UInt8.self
                    ).baseAddress else { return }
                    let result = runcore_lxst_send_frame(
                        activeHandle,
                        1,
                        baseAddress,
                        Int32(frame.count)
                    )
                    if result != 0 {
                        Task { @MainActor [weak self] in
                            self?.lxstAudioStatus =
                                "LXST audio transmission failed"
                        }
                    }
                }
            }
        }
    }

    fileprivate func receiveLXSTState(
        _ callStatus: LXSTCallStatus,
        remoteIdentityHash: String
    ) {
        lxstCallStatus = callStatus
        if !remoteIdentityHash.isEmpty {
            lxstRemoteIdentityHash = remoteIdentityHash
        }
        if callStatus == .available {
            lxstRemoteIdentityHash = ""
        }
        if callStatus == .established {
            lxstAudioEngine.start()
        } else if callStatus == .available
                    || callStatus == .busy
                    || callStatus == .rejected {
            lxstAudioEngine.stop()
            lxstAudioStatus = "Audio inactive"
        }
    }

    fileprivate func receiveLXSTFrame(codec: Int32, data: Data) {
        if codec == 1 {
            lxstAudioEngine.receiveOpusFrame(data)
        }
        lxstFrameHandler?(codec, data)
    }

    func connectWiFiLAN(host: String, port: UInt16) -> Bool {
        guard handle != 0,
              PacketInterfaceManager.shared.isActive(.wifiLocalNetwork) else {
            return false
        }
        let result = host.withCString {
            runcore_connect_tcp_interface(handle, $0, Int32(port))
        }
        return result == 0
    }

    func connectWiFiLANAsync(
        host: String,
        port: UInt16
    ) async -> Bool {
        guard handle != 0,
              PacketInterfaceManager.shared.isActive(.wifiLocalNetwork) else {
            return false
        }
        let activeHandle = handle
        return await withCheckedContinuation { continuation in
            outboundCoreQueue.async {
                let result = host.withCString {
                    runcore_connect_tcp_interface(
                        activeHandle,
                        $0,
                        Int32(port)
                    ) == 0
                }
                continuation.resume(returning: result)
            }
        }
    }

    func disconnectWiFiLAN() {
        guard handle != 0 else { return }
        _ = runcore_disconnect_tcp_interface(handle)
    }

    func disconnectWiFiLANAsync() async {
        guard handle != 0 else { return }
        let activeHandle = handle
        await withCheckedContinuation { continuation in
            outboundCoreQueue.async {
                _ = runcore_disconnect_tcp_interface(activeHandle)
                continuation.resume()
            }
        }
    }

    var wifiLANConnectionState: Int32 {
        guard handle != 0 else { return 0 }
        return runcore_tcp_interface_state(handle)
    }

    func wifiLANConnectionStateAsync() async -> Int32 {
        guard handle != 0 else { return 0 }
        let activeHandle = handle
        return await withCheckedContinuation { continuation in
            outboundCoreQueue.async {
                continuation.resume(
                    returning: runcore_tcp_interface_state(activeHandle)
                )
            }
        }
    }

    func connectRaspberryPiAsync(
        host: String,
        port: UInt16
    ) async -> Bool {
        guard handle != 0,
              PacketInterfaceManager.shared.isActive(.raspberryPi) else {
            return false
        }
        let activeHandle = handle
        return await withCheckedContinuation { continuation in
            outboundCoreQueue.async {
                let result = host.withCString {
                    runcore_connect_raspberry_pi_interface(
                        activeHandle,
                        $0,
                        Int32(port)
                    ) == 0
                }
                continuation.resume(returning: result)
            }
        }
    }

    func disconnectRaspberryPiAsync() async {
        guard handle != 0 else { return }
        let activeHandle = handle
        await withCheckedContinuation { continuation in
            outboundCoreQueue.async {
                _ = runcore_disconnect_raspberry_pi_interface(activeHandle)
                continuation.resume()
            }
        }
    }

    func raspberryPiConnectionStateAsync() async -> Int32 {
        guard handle != 0 else { return 0 }
        let activeHandle = handle
        return await withCheckedContinuation { continuation in
            outboundCoreQueue.async {
                continuation.resume(
                    returning: runcore_raspberry_pi_interface_state(activeHandle)
                )
            }
        }
    }

    func feed(_ packet: Data) {
        guard handle != 0, !packet.isEmpty else {
            return
        }

        let activeHandle = handle
        inboundPacketQueue.async {
            packet.withUnsafeBytes { rawBuffer in
                guard let baseAddress =
                        rawBuffer.bindMemory(
                            to: UInt8.self
                        ).baseAddress else {
                    return
                }
                let result = runcore_raw_interface_receive(
                    activeHandle,
                    baseAddress,
                    Int32(packet.count)
                )

                #if DEBUG
                privacySafeLog(
                    """
                    RETICULUM CORE RECEIVE
                    Bytes: \(packet.count)
                    Result: \(result)
                    """
                )
                #endif
            }
        }

        // BLE traffic can wake the app after iOS suspended its timers.
        // Use that opportunity to send an overdue scheduled announce.
        checkScheduledAutomaticAnnounce()
    }

    func announce() -> Bool {
        guard handle != 0,
              runcore_announce(handle) == 0 else {
            return false
        }
        recordAnnounce(at: Date())
        return true
    }

    func automaticAnnounceSettingsDidChange() {
        checkScheduledAutomaticAnnounce()
    }

    func setAnnounceLocation(_ location: CLLocation?) {
        guard handle != 0 else { return }
        guard let location else {
            _ = runcore_set_announce_location(
                handle, 0, 0, 0, 0, 0
            )
            return
        }
        _ = runcore_set_announce_location(
            handle,
            location.coordinate.latitude,
            location.coordinate.longitude,
            location.horizontalAccuracy,
            Int64(location.timestamp.timeIntervalSince1970),
            1
        )
    }

    func setTelemetryTimeEnabled(_ enabled: Bool) {
        guard handle != 0 else { return }
        _ = runcore_set_telemetry_time_enabled(
            handle,
            enabled ? 1 : 0
        )
    }

    private func applySavedTelemetryPreferences() {
        let defaults = UserDefaults.standard
        setTelemetryTimeEnabled(
            defaults.bool(
                forKey: TelemetryPreferenceKey.shareTimestamp
            )
        )

        let shareLocation = defaults.bool(
            forKey: TelemetryPreferenceKey.shareLocation
        )
        setAnnounceLocation(
            shareLocation
                ? LocationTelemetryManager.shared.location
                : nil
        )
    }

    func radioDataChannelReady() {
        requestAutomaticAnnounce(
            reason: "Bluetooth route advertised",
            minimumInterval: 0
        )
    }

    func setAppIsActive(_ isActive: Bool) {
        appIsActive = isActive
        if isActive {
            startRouteMaintenance()
        } else {
            routeRefreshTimer?.invalidate()
            routeRefreshTimer = nil
        }
    }

    func send(
        text: String,
        destinationHash: String,
        clientID: UUID,
        direct: Bool = true
    ) -> Bool {
        guard handle != 0 else {
            return false
        }
        return destinationHash.withCString {
            destination in
            text.withCString { content in
                clientID.uuidString.withCString {
                    clientIDString in
                    runcore_send_text(
                        handle,
                        destination,
                        content,
                        direct ? 1 : 0,
                        clientIDString
                    ) == 0
                }
            }
        }
    }

    func sendAsync(
        text: String,
        destinationHash: String,
        clientID: UUID,
        direct: Bool = true
    ) async -> Bool {
        guard handle != 0 else { return false }
        let activeHandle = handle
        return await withCheckedContinuation { continuation in
            outboundCoreQueue.async {
                let result = destinationHash.withCString { destination in
                    text.withCString { content in
                        clientID.uuidString.withCString { identifier in
                            runcore_send_text(
                                activeHandle,
                                destination,
                                content,
                                direct ? 1 : 0,
                                identifier
                            ) == 0
                        }
                    }
                }
                continuation.resume(returning: result)
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
        guard handle != 0 else {
            privacySafeLog(
                "ATTACHMENT SEND FAILED: Reticulum core not running"
            )
            return false
        }

        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            privacySafeLog(
                """
                ATTACHMENT SEND FAILED
                File does not exist at:
                \(fileURL.path)
                """
            )
            return false
        }

        let attributes =
            try? FileManager.default.attributesOfItem(
                atPath: fileURL.path
            )

        let fileSize =
            (attributes?[.size] as? NSNumber)?
            .intValue ?? 0

        privacySafeLog(
            """
            ATTACHMENT SEND START
            Path: \(fileURL.path)
            Name: \(name)
            MIME: \(mimeType)
            Size: \(fileSize) bytes
            Destination: \(destinationHash)
            Client ID: \(clientID.uuidString)
            """
        )

        let result =
            destinationHash.withCString { destination in
                caption.withCString { content in
                    fileURL.path.withCString { path in
                        name.withCString { filename in
                            mimeType.withCString { mime in
                                clientID.uuidString.withCString {
                                    identifier in

                                    runcore_send_attachment(
                                        handle,
                                        destination,
                                        content,
                                        path,
                                        filename,
                                        mime,
                                        identifier
                                    )
                                }
                            }
                        }
                    }
                }
            }

        privacySafeLog(
            "ATTACHMENT SEND RESULT: \(result)"
        )

        return result == 0
    }

    func sendAttachmentAsync(
        at fileURL: URL,
        name: String,
        mimeType: String,
        caption: String,
        destinationHash: String,
        clientID: UUID
    ) async -> Bool {
        guard handle != 0,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }
        let activeHandle = handle
        let path = fileURL.path
        return await withCheckedContinuation { continuation in
            outboundCoreQueue.async {
                let result = destinationHash.withCString { destination in
                    caption.withCString { content in
                        path.withCString { filePath in
                            name.withCString { filename in
                                mimeType.withCString { mime in
                                    clientID.uuidString.withCString {
                                        identifier in
                                        runcore_send_attachment(
                                            activeHandle,
                                            destination,
                                            content,
                                            filePath,
                                            filename,
                                            mime,
                                            identifier
                                        ) == 0
                                    }
                                }
                            }
                        }
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }

    func receiveStatus(
        clientID: String,
        status: String
    ) {
        let components = status.split(
            separator: "|",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let statusName = String(components[0])
        let detail = components.count > 1
            ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        privacySafeLog(
            "LXMF STATUS clientID='\(clientID)' status='\(statusName)'" +
            (detail.map { " detail='\($0)'" } ?? "")
        )

        guard let id = UUID(uuidString: clientID) else {
            privacySafeLog("LXMF STATUS FAILED: invalid client ID")
            return
        }

        guard let value =
                LXMFOutgoingStatus(rawValue: statusName)
        else {
            privacySafeLog(
                "LXMF STATUS FAILED: unknown status \(statusName)"
            )
            return
        }

        if value == .failed {
            let failureReason = detail.flatMap {
                $0.isEmpty ? nil : $0
            } ?? "Reticulum delivery attempt failed"
            LXMFManager.shared.recordTransientFailure(
                id: id,
                reason: failureReason
            )
        } else {
            LXMFManager.shared.updateMessageStatus(
                id: id,
                status: value
            )
        }
    }

    func transmit(_ packet: Data) {
        guard !packet.isEmpty else {
            privacySafeLog("Reticulum core attempted empty transmission")
            return
        }

        let packetType = packet[0] & 0x03

        let destinationTypeBits =
            (packet[0] >> 2) & 0x03

        let contextValue: UInt8? =
            packet.count > 18
                ? packet[18]
                : nil

        let typeName: String
        switch packetType {
        case 0x00:
            typeName = "Data"
        case 0x01:
            typeName = "Announce"
        case 0x02:
            typeName = "Link Request"
        case 0x03:
            typeName = "Proof"
        default:
            typeName = "Unknown"
        }

        let destinationName: String
        switch destinationTypeBits {
        case 0x00:
            destinationName = "Single"
        case 0x01:
            destinationName = "Group"
        case 0x02:
            destinationName = "Plain"
        case 0x03:
            destinationName = "Link"
        default:
            destinationName = "Unknown"
        }

        #if DEBUG
        privacySafeLog(
            """
            RETICULUM CORE TRANSMIT
            Type: \(typeName)
            Destination: \(destinationName)
            Context: \(contextValue.map {
                String(format: "0x%02X", $0)
            } ?? "Unavailable")
            First byte: 0x\(String(
                format: "%02X",
                packet[0]
            ))
            Bytes: \(packet.count)
            """
        )
        #endif

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
        attachmentType: Int32,
        location: RemoteNodeLocation?
    ) {
        guard let sourceHash = Data(hex: sourceHex),
              let localHash = Data(
                hex: destinationHash
              ),
              sourceHash != localHash else {
            return
        }
        if let location {
            let existing = remoteNodeLocations[sourceHex]
            let incomingDate =
                location.telemetryDate ?? location.receivedAt
            let existingDate = existing.flatMap {
                $0.telemetryDate ?? $0.receivedAt
            }
            if existingDate.map({ incomingDate >= $0 }) ?? true {
                remoteNodeLocations[sourceHex] = location
                pruneRemoteNodeLocations()
                persistRemoteNodeLocations()
            }
        }
        if let envelope = GroupWireEnvelope.decode(content) {
            let received = GroupMessageStore.shared.receive(
                envelope: envelope,
                sourceHash: sourceHex.lowercased(),
                timestamp: Date(timeIntervalSince1970: timestamp),
                attachmentPath: attachmentPath.isEmpty ? nil : attachmentPath,
                attachmentName: attachmentName.isEmpty ? nil : attachmentName,
                attachmentMIME: attachmentMIME.isEmpty ? nil : attachmentMIME,
                attachmentType: attachmentType
            )
            if received {
                status = "Group message received from \(sourceHex.prefix(8))"
                requestAutomaticAnnounce(reason: "Group return route refreshed", minimumInterval: 15)
            }
            return
        }
        var identifierMaterial = Data()
        identifierMaterial.append(sourceHash)
        identifierMaterial.append(Data(title.utf8))
        identifierMaterial.append(Data(content.utf8))
        identifierMaterial.append(Data(attachmentPath.utf8))
        identifierMaterial.append(Data(attachmentName.utf8))
        identifierMaterial.append(Data(attachmentMIME.utf8))
        identifierMaterial.append(
            withUnsafeBytes(
                of: timestamp.bitPattern.bigEndian
            ) {
                Data($0)
            }
        )
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
            attachmentType: attachmentType == 1
                ? .photo
                : (attachmentMIME.hasPrefix("audio/")
                    ? .voiceNote
                    : (attachmentType == 2 ? .file : nil))
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

    private func persistRemoteNodeLocations() {
        let locations = Array(remoteNodeLocations.values)
        guard let data = try? JSONEncoder().encode(
            locations
        ) else {
            return
        }
        UserDefaults.standard.set(
            data,
            forKey: remoteNodeLocationsStorageKey
        )
    }

    private func pruneRemoteNodeLocations(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(
            -Self.remoteNodeStaleInterval
        )
        let retained = remoteNodeLocations.values
            .filter { $0.receivedAt >= cutoff }
            .sorted { $0.receivedAt > $1.receivedAt }
            .prefix(Self.maximumStoredRemoteNodes)
        remoteNodeLocations = Dictionary(
            uniqueKeysWithValues: retained.map {
                ($0.sourceHash, $0)
            }
        )
    }

    private func loadRemoteNodeLocations() {
        guard let data = UserDefaults.standard.data(
                    forKey: remoteNodeLocationsStorageKey
              ),
              let locations = try? JSONDecoder().decode(
                    [RemoteNodeLocation].self,
                    from: data
              )
        else {
            return
        }
        remoteNodeLocations = Dictionary(
            uniqueKeysWithValues: locations.map {
                ($0.sourceHash, $0)
            }
        )
        pruneRemoteNodeLocations()
    }

    func recordLog(
        level: Int32,
        message: String
    ) {
        let lowered = message.lowercased()
        guard lowered.contains("link") ||
                lowered.contains("lxmf") ||
                lowered.contains("path") ||
                lowered.contains("attachment") ||
                lowered.contains("announce") ||
                lowered.contains("deliver") ||
                lowered.contains("resource") ||
                lowered.contains("proof") ||
                lowered.contains("timeout") ||
                lowered.contains("part request") ||
                lowered.contains("cancel") ||
                lowered.contains("failed") ||
                lowered.contains("error") else {
            return
        }
        status = message
        privacySafeLog(
            "Reticulum core [\(level)]: \(message)"
        )
    }

    private func startRouteMaintenance() {
        routeRefreshTimer?.invalidate()
        guard appIsActive else {
            routeRefreshTimer = nil
            return
        }
        routeRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { _ in
            Task { @MainActor [weak self] in
                self?.checkScheduledAutomaticAnnounce()
            }
        }
        routeRefreshTimer?.tolerance = 3
        checkScheduledAutomaticAnnounce()
    }

    private func checkScheduledAutomaticAnnounce() {
        let defaults = UserDefaults.standard
        guard defaults.bool(
            forKey: AutomaticAnnouncePreferenceKey.enabled
        ) else {
            return
        }
        guard !LXMFManager.shared.hasActiveMessageTraffic else {
            return
        }
        let storedMinutes = defaults.integer(
            forKey: AutomaticAnnouncePreferenceKey
                .intervalMinutes
        )
        let interval =
            AutomaticAnnounceInterval(
                rawValue: storedMinutes
            ) ?? .thirtyMinutes
        requestAutomaticAnnounce(
            reason: "Scheduled identity announcement sent",
            minimumInterval: interval.timeInterval
        )
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
        recordAnnounce(at: Date())
        status = reason
    }

    private func recordAnnounce(at date: Date) {
        lastAutomaticAnnounce = date
        UserDefaults.standard.set(
            date,
            forKey: AutomaticAnnouncePreferenceKey
                .lastAnnouncedAt
        )
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
