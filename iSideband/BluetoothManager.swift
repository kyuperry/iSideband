import Foundation
@preconcurrency import CoreBluetooth
import Combine
import CryptoKit
import UserNotifications

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
}

@MainActor
final class BluetoothManager:
    NSObject,
    ObservableObject,
    UNUserNotificationCenterDelegate
{
    private let packetDecoder = RNodePacketDecoder()
    private let packetRouter = RNodePacketRouter()
    private let frameAssembler = RNodeFrameAssembler()
    private let reticulumDecoder = ReticulumPacketDecoder()
    private let announceDecoder = ReticulumAnnounceDecoder()
    private let lxmfMessageCodec = LXMFMessageCodec()
    private var announceEventTracker =
        ReticulumAnnounceEventTracker()
    private var receivedLXMFMessageIDs = Set<Data>()
    
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    
    @Published private(set) var connectedDeviceID: UUID?
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var connectingDeviceID: UUID?
    @Published private(set) var connectionMessage = "Not connected"
    
    @Published private(set) var serviceCount = 0
    @Published private(set) var receivedData = Data()
    @Published var packetsReceived = 0
    @Published var lastPacketTime: Date?
    @Published var lastRSSI: Int?
    @Published var firmwareVersion = "Unknown"
    @Published var boardName = "Unknown"
    @Published var batteryPercent: Int?
    @Published var batteryState: RNodeBatteryState?
    @Published var radioFrequency: UInt32?
    @Published var radioBandwidth: UInt32?
    @Published var transmitPower: Int?
    @Published var spreadingFactor: Int?
    @Published var codingRate: Int?
    @Published var temperature: Double?
    @Published var radioReady = false
    @Published var receivedBytes: UInt32?
    @Published var transmittedBytes: UInt32?
    @Published private(set) var reticulumBytesReceived = 0
    @Published private(set) var reticulumBytesTransmitted = 0
    @Published private(set) var bluetoothBytesWritten = 0
    @Published private(set) var bluetoothBytesReceived = 0
    @Published private(set) var lastInboundDiagnostic =
        "No inbound packet inspected"
    @Published var packetRSSI: Int?
    @Published var packetSNR: Double?
    @Published var satelliteCount: Int?
    @Published var uptimeSeconds: UInt32?
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var reconnectPeripheral: CBPeripheral?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maximumReconnectAttempts = 4
    private var manualDisconnectRequested = false
    private var rssiTimer: Timer?
    
    private var rnodeWriteCharacteristic: CBCharacteristic?
    private var rnodeNotifyCharacteristic: CBCharacteristic?
    private var pendingRNodeWriteChunks: [Data] = []
    private var isRNodeWriteDrainScheduled = false
    private let batteryNotificationMilestones = [50, 25]
    private var sentBatteryMilestones = Set<Int>()
    private var lastBatteryNotificationPercent: Int?
    private var hasRNodeBatteryTelemetry = false
    
    override init() {
        super.init()
        
        UNUserNotificationCenter.current().delegate = self
        
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                print(
                    "Notification permission error: " +
                    error.localizedDescription
                )
            } else {
                print("Notification permission granted: \(granted)")
            }
        }
        
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey:
                    "com.kyleperry.iSideband.rnode-central",
                CBCentralManagerOptionShowPowerAlertKey:
                    true
            ]
        )

        // Do not wait for a SwiftUI view to appear. iOS may create this
        // manager solely to restore an RNode connection in the background.
        // The LXMF receiver must already exist when restored BLE bytes arrive.
        LXMFManager.shared.start(bluetooth: self)
    }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
        @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("Foreground notification delegate called")
        completionHandler([.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler:
        @escaping () -> Void
    ) {
        let userInfo =
            response.notification.request.content.userInfo
        let route: NotificationRoute?

        if let sourceHash =
                userInfo["sourceHash"] as? String {
            route = .message(sourceHash: sourceHash)
        } else if let destinationHash =
                    userInfo["destinationHash"] as? String {
            route = .discoveredPeer(
                destinationHash: destinationHash
            )
        } else {
            route = nil
        }

        Task { @MainActor in
            if let route {
                NotificationNavigationRouter.shared.receive(
                    route: route
                )
            }
            completionHandler()
        }
    }
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionMessage = "Bluetooth is not ready"
            return
        }
        
        devices.removeAll()
        isScanning = true
        connectionMessage = "Scanning for nearby devices…"
        
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ]
        )
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        
        if connectedDeviceID == nil {
            connectionMessage = "Not connected"
        }
    }
    
    func connect(to device: DiscoveredDevice) {
        stopScanning()

        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        manualDisconnectRequested = false
        reconnectPeripheral = device.peripheral
        connectingDeviceID = device.id
        connectionMessage = "Connecting to \(device.name)…"
        
        centralManager.connect(
            device.peripheral,
            options: nil
        )
    }
    
    func disconnect() {
        guard let connectedPeripheral else {
            return
        }

        manualDisconnectRequested = true
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        reconnectPeripheral = nil

        centralManager.cancelPeripheralConnection(
            connectedPeripheral
        )
    }
    
    func sendToRNode(_ data: Data)
    {
        
        guard
            let connectedPeripheral,
            let rnodeWriteCharacteristic
        else {
            connectionMessage = "RNode data channel is not ready"
            return
        }
        
        let escaped = escapeKISSFrame(data)
        let writeType: CBCharacteristicWriteType =
            .withoutResponse
        let maximumLength =
            connectedPeripheral.maximumWriteValueLength(
                for: writeType
            )

        guard maximumLength > 0 else {
            connectionMessage =
                "RNode BLE write size is unavailable"
            return
        }

        var offset = 0

        while offset < escaped.count {
            let end = min(
                offset + maximumLength,
                escaped.count
            )
            let chunk = escaped.subdata(
                in: offset..<end
            )

            pendingRNodeWriteChunks.append(chunk)
            offset = end
        }
        drainRNodeWriteQueue()
    }

    private func drainRNodeWriteQueue() {
        guard !isRNodeWriteDrainScheduled,
              !pendingRNodeWriteChunks.isEmpty,
              let connectedPeripheral,
              let rnodeWriteCharacteristic,
              connectedPeripheral.state == .connected,
              connectedPeripheral.canSendWriteWithoutResponse
        else {
            return
        }

        let chunk = pendingRNodeWriteChunks.removeFirst()
        connectedPeripheral.writeValue(
            chunk,
            for: rnodeWriteCharacteristic,
            type: .withoutResponse
        )
        bluetoothBytesWritten += chunk.count
        print("Wrote \(chunk.count) bytes to RNode BLE stream")

        isRNodeWriteDrainScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.isRNodeWriteDrainScheduled = false
            self.drainRNodeWriteQueue()
        }
    }
    private func escapeKISSFrame(_ frame: Data) -> Data {
        guard frame.count >= 2 else {
            return frame
        }
        
        var escaped = Data()
        escaped.append(0xC0)
        
        for byte in frame.dropFirst().dropLast() {
            switch byte {
            case 0xC0:
                escaped.append(0xDB)
                escaped.append(0xDC)
                
            case 0xDB:
                escaped.append(0xDB)
                escaped.append(0xDD)
                
            default:
                escaped.append(byte)
            }
        }
        
        escaped.append(0xC0)
        return escaped
    }
    private func addOrUpdateDevice(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        let advertisedName =
        advertisementData[
            CBAdvertisementDataLocalNameKey
        ] as? String
        
        let name =
        advertisedName ??
        peripheral.name ??
        "Unknown Bluetooth Device"
        
        let device = DiscoveredDevice(
            id: peripheral.identifier,
            peripheral: peripheral,
            name: name,
            rssi: rssi.intValue
        )
        
        if let index = devices.firstIndex(
            where: { $0.id == device.id }
        ) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        
        devices.sort { $0.rssi > $1.rssi }
    }
    
    private func clearConnectionState() {
        rssiTimer?.invalidate()
        rssiTimer = nil

        connectingDeviceID = nil
        connectedDeviceID = nil
        connectedPeripheral = nil
        
        rnodeWriteCharacteristic = nil
        rnodeNotifyCharacteristic = nil
        pendingRNodeWriteChunks.removeAll()
        isRNodeWriteDrainScheduled = false
        batteryPercent = nil
        batteryState = nil
        satelliteCount = nil
        uptimeSeconds = nil
        hasRNodeBatteryTelemetry = false
        sentBatteryMilestones.removeAll()
        lastBatteryNotificationPercent = nil
        
        serviceCount = 0
    }

    private func scheduleReconnect(
        to peripheral: CBPeripheral
    ) {
        guard !manualDisconnectRequested,
              centralManager.state == .poweredOn,
              reconnectAttempt <
                maximumReconnectAttempts else {
            if reconnectAttempt >=
                maximumReconnectAttempts {
                connectionMessage =
                    "RNode unavailable — reconnect manually"
            }
            return
        }

        reconnectTask?.cancel()
        reconnectAttempt += 1

        let attempt = reconnectAttempt
        let delay = min(
            pow(2.0, Double(attempt - 1)),
            8.0
        )

        connectionMessage =
            "Reconnecting to \(peripheral.name ?? "RNode") in \(Int(delay))s…"

        reconnectTask = Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(delay)
            )

            guard !Task.isCancelled,
                  !manualDisconnectRequested,
                  centralManager.state == .poweredOn,
                  connectedDeviceID == nil else {
                return
            }

            connectingDeviceID = peripheral.identifier
            connectionMessage =
                "Reconnecting to \(peripheral.name ?? "RNode")…"

            centralManager.connect(
                peripheral,
                options: nil
            )
        }
    }
    private func sendLowBatteryNotification(percent: Int) {
        for milestone in batteryNotificationMilestones
        where percent > milestone {
            sentBatteryMilestones.remove(milestone)
        }

        let previousPercent = lastBatteryNotificationPercent
        let crossedMilestone = batteryNotificationMilestones
            .filter { !sentBatteryMilestones.contains($0) }
            .filter { milestone in
                if percent == milestone {
                    return true
                }

                guard let previousPercent else {
                    return false
                }

                return previousPercent > milestone
                    && percent < milestone
            }
            .min()

        lastBatteryNotificationPercent = percent

        guard let milestone = crossedMilestone else {
            return
        }

        sentBatteryMilestones.insert(milestone)

        guard NotificationPreferences.batteryEnabled(
            at: milestone
        ) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "RNode Battery \(milestone)%"
        content.body =
            "Your connected RNode battery has reached \(milestone)%."
        if NotificationPreferences.soundsEnabled {
            content.sound = .default
        }
        
        let request = UNNotificationRequest(
            identifier: "rnode-low-battery",
            content: content,
            trigger: nil
        )
        
        let center = UNUserNotificationCenter.current()
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                    || settings.authorizationStatus == .ephemeral
            else {
                print(
                    "Low-battery notification skipped: notifications are not authorized"
                )
                return
            }

            do {
                try await center.add(request)
                print("Low-battery notification sent")
            } catch {
                print(
                    "Low-battery notification failed: " +
                    error.localizedDescription
                )
            }
        }
        
    }
    func restartRNode() {
        let frame = Data([
            0xC0,
            0x55,
            0xF8,
            0xC0
        ])
        
        sendToRNode(frame)
    }
    
    func turnRadioOff() {
        let frame = Data([
            0xC0,
            0x3F,
            0x00,
            0xC0
        ])
        
        sendToRNode(frame)
    }
    func requestRNodeDetails() {
        let defaults = UserDefaults.standard

        let frequencyText =
            defaults.string(
                forKey: "radioFrequencyMHz"
            ) ?? "915.000"

        let bandwidthText =
            defaults.string(
                forKey: "radioBandwidthKHz"
            ) ?? "125"

        let powerText =
            defaults.string(
                forKey: "radioTransmitPowerDBm"
            ) ?? "22"

        let spreadingFactorText =
            defaults.string(
                forKey: "radioSpreadingFactor"
            ) ?? "7"

        let codingRateText =
            defaults.string(
                forKey: "radioCodingRate"
            ) ?? "5"

        guard
            let frequencyMHz =
                Double(frequencyText),
            let bandwidthKHz =
                Double(bandwidthText),
            let power =
                Int(powerText),
            let sf =
                Int(spreadingFactorText),
            let cr =
                Int(codingRateText)
        else {
            connectionMessage =
                "Saved LoRa configuration is invalid"

            requestRNodeTelemetry()
            return
        }

        let frequencyHzDouble =
            frequencyMHz * 1_000_000

        let bandwidthHzDouble =
            bandwidthKHz * 1_000

        guard
            frequencyHzDouble >= 137_000_000,
            frequencyHzDouble <= 1_020_000_000,
            bandwidthHzDouble >= 7_800,
            bandwidthHzDouble <= 500_000,
            (0...30).contains(power),
            (5...12).contains(sf),
            (5...8).contains(cr)
        else {
            connectionMessage =
                "Saved LoRa configuration is outside the supported range"

            requestRNodeTelemetry()
            return
        }

        let configuration =
            RNodeRadioConfiguration(
                frequencyHz:
                    UInt32(
                        frequencyHzDouble.rounded()
                    ),
                bandwidthHz:
                    UInt32(
                        bandwidthHzDouble.rounded()
                    ),
                transmitPowerDBm: power,
                spreadingFactor: sf,
                codingRate: cr
            )

        connectionMessage =
            "Applying saved LoRa configuration…"

        applyRadioConfiguration(
            configuration
        ) { result in
            switch result {
            case .success:
                self.connectionMessage =
                    "RNode data channel ready"

                print(
                    """
                    Saved LoRa configuration applied on connection
                    Frequency: \(frequencyMHz) MHz
                    Bandwidth: \(bandwidthKHz) kHz
                    TX power: \(power) dBm
                    Spreading factor: \(sf)
                    Coding rate: 4/\(cr)
                    """
                )

            case .failure(let error):
                self.connectionMessage =
                    "Radio configuration failed: \(error.localizedDescription)"

                print(
                    "Could not apply saved LoRa configuration:",
                    error.localizedDescription
                )
            }

            self.requestRNodeTelemetry()
        }
    }
    private func requestRNodeTelemetry() {
        let frames: [Data] = [
            // Firmware version
            Data([
                0xC0,
                0x50,
                0xFF,
                0xC0
            ]),

            // Total radio bytes received
            Data([
                0xC0,
                0x21,
                0xFF,
                0xC0
            ]),

            // Total radio bytes transmitted
            Data([
                0xC0,
                0x22,
                0xFF,
                0xC0
            ]),

            // RSSI of the last radio packet
            Data([
                0xC0,
                0x23,
                0xFF,
                0xC0
            ]),

            // SNR of the last radio packet
            Data([
                0xC0,
                0x24,
                0xFF,
                0xC0
            ]),

            // GPS satellite count
            Data([
                0xC0,
                0x2A,
                0xFF,
                0xC0
            ]),

            // Device uptime
            Data([
                0xC0,
                0x2B,
                0xFF,
                0xC0
            ])
        ]

        for (index, frame) in frames.enumerated() {
            DispatchQueue.main.asyncAfter(
                deadline:
                    .now() +
                    0.25 +
                    Double(index) * 0.2
            ) {
                guard
                    self.connectedDeviceID != nil
                else {
                    return
                }

                self.sendToRNode(frame)
            }
        }
    }

    func sendRadioPayload(_ payload: Data) {
        guard !payload.isEmpty else {
            print("Cannot send an empty radio payload")
            return
        }
        
        var frame = Data([
            0xC0,
            0x00
        ])
        
        frame.append(payload)
        frame.append(0xC0)
        
        reticulumBytesTransmitted += payload.count
        lastPacketTime = Date()
        sendToRNode(frame)
        
        print(
            "Radio payload handed to RNode: \(payload.count) bytes"
        )
    }
    func sendMessage(_ text: String) {
        guard let payload = text.data(using: .utf8) else {
            print("Unable to encode message")
            return
        }
        
        sendRadioPayload(payload)
        
        print("Sent raw radio-data test: \(text)")
    }
    private func reticulumPacketHash(
        for packet: DecodedReticulumPacket
    ) -> Data? {
        guard packet.raw.count >= 3 else {
            return nil
        }

        var hashablePart = Data([
            packet.raw[0] & 0x0F
        ])

        switch packet.headerType {
        case .normal:
            hashablePart.append(
                packet.raw.dropFirst(2)
            )

        case .transport:
            guard packet.raw.count > 18 else {
                return nil
            }

            hashablePart.append(
                packet.raw.dropFirst(18)
            )
        }

        return Data(
            SHA256.hash(data: hashablePart)
        )
    }
    private func handleIncomingLXMF(
        _ packet: DecodedReticulumPacket
    ) {
        guard packet.packetType == .data else {
            lastInboundDiagnostic =
                "Ignored non-data Reticulum packet"
            return
        }
        guard packet.destinationType == .single else {
            lastInboundDiagnostic =
                "Unsupported Direct/link packet; use Opportunistic"
            return
        }
        guard packet.context ==
                ReticulumPacketContext.none else {
            lastInboundDiagnostic =
                "Unsupported packet context \(packet.contextRawValue)"
            return
        }

        do {
            guard let identity =
                    try ReticulumIdentityStore.shared
                        .loadIdentity()
            else {
                return
            }

            let localDestinationHash =
                try ReticulumAnnounceEncoder()
                    .destinationHash(
                        identity: identity,
                        destinationName:
                            "lxmf.delivery"
                    )
            guard packet.destinationHash ==
                    localDestinationHash else {
                lastInboundDiagnostic =
                    "Packet addressed to a different identity"
                return
            }

            let plaintext: Data
            do {
                plaintext =
                    try identity.decrypt(packet.payload)
            } catch {
                plaintext =
                    try ReticulumRatchet.shared.decrypt(
                        packet.payload,
                        identityHash:
                            identity.identityHash
                    )
            }
            var packedLXMF = Data()
            packedLXMF.append(
                localDestinationHash
            )
            packedLXMF.append(plaintext)
            let message = try lxmfMessageCodec.decode(
                packedLXMF,
                expectedDestinationHash:
                    localDestinationHash
            ) { sourceHash in
                ReticulumAnnounceStore.shared
                    .publicKey(for: sourceHash)
            }

            guard message.sourceHash !=
                    localDestinationHash,
                  receivedLXMFMessageIDs
                    .insert(message.id).inserted
            else {
                lastInboundDiagnostic =
                    "Duplicate or self-originated message"
                return
            }

            guard LXMFIncomingMessageStore.shared
                    .save(message)
            else {
                lastInboundDiagnostic =
                    "Message was already saved"
                return
            }

            lastInboundDiagnostic =
                "Valid LXMF message received"

            let senderName =
                LXMFContactStore.shared.contact(
                    for: message.sourceHashHex
                )?.displayName ??
                ReticulumAnnounceStore.shared
                    .announce(
                        for: message.sourceHashHex
                    )?.displayName
            LXMFMessageNotificationManager.shared
                .notify(
                    message: message,
                    senderName: senderName
                )

            packetsReceived += 1
            lastPacketTime = Date()

            print(
                """
                VALID LXMF MESSAGE RECEIVED
                Source: \(message.sourceHashHex)
                Content: \(message.content)
                """
            )
        } catch {
            lastInboundDiagnostic =
                "LXMF rejected: \(error)"
            print(
                "Incoming LXMF message rejected:",
                error.localizedDescription
            )
        }
    }
}
    extension BluetoothManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(
        _ central: CBCentralManager
    ) {
        Task { @MainActor in
            bluetoothState = central.state

            if central.state != .poweredOn {
                reconnectTask?.cancel()
                reconnectTask = nil
                devices.removeAll()
                isScanning = false
                clearConnectionState()
                connectionMessage = "Bluetooth unavailable"
            } else if connectedDeviceID == nil {
                if let reconnectPeripheral,
                   !manualDisconnectRequested {
                    scheduleReconnect(
                        to: reconnectPeripheral
                    )
                } else {
                    connectionMessage = "Bluetooth ready"
                }
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        guard let peripherals =
                dict[
                    CBCentralManagerRestoredStatePeripheralsKey
                ] as? [CBPeripheral],
              let peripheral = peripherals.first
        else {
            return
        }

        Task { @MainActor in
            // State restoration can be the app's first callback after iOS
            // launches it in the background. This is intentionally idempotent.
            LXMFManager.shared.start(bluetooth: self)

            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
            manualDisconnectRequested = false
            reconnectPeripheral = peripheral
            connectedPeripheral = peripheral
            connectedDeviceID = peripheral.identifier
            connectedDeviceName =
                peripheral.name ?? "RNode"
            connectingDeviceID = nil
            connectionMessage =
                "Restored connection to \(peripheral.name ?? "RNode")"

            peripheral.delegate = self
            peripheral.discoverServices(nil)
            peripheral.readRSSI()

            print(
                "Restored RNode Bluetooth connection:",
                peripheral.identifier
            )
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in

            let advertisedName =
                advertisementData[
                    CBAdvertisementDataLocalNameKey
                ] as? String

            let name =
                advertisedName ??
                peripheral.name ??
                ""
            print("DISCOVERED:", name.isEmpty ? "Unnamed" : name, peripheral.identifier, RSSI)
            
            //guard name.localizedCaseInsensitiveContains("RNode") else {
            //return
            //}
// Only show devices that advertise themselves as RNodes
            guard name.localizedCaseInsensitiveContains("RNode") else {
             return
            }
            lastRSSI = RSSI.intValue

            addOrUpdateDevice(
                peripheral: peripheral,
                advertisementData: advertisementData,
                rssi: RSSI
            )
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) { print("CONNECTED TO:", peripheral.name ?? "Unnamed", peripheral.identifier)
        Task { @MainActor in
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
            manualDisconnectRequested = false
            reconnectPeripheral = peripheral
            connectedPeripheral = peripheral
            connectingDeviceID = nil
            connectedDeviceID = peripheral.identifier
            connectedDeviceName =
                peripheral.name ?? "RNode"

            connectionMessage =
                "Connected to \(peripheral.name ?? "RNode")"

            peripheral.delegate = self
            peripheral.discoverServices(nil)
            peripheral.readRSSI()

            rssiTimer?.invalidate()
            rssiTimer = Timer.scheduledTimer(
                withTimeInterval: 2.0,
                repeats: true
            ) { _ in
                guard peripheral.state ==
                        .connected else {
                    return
                }
                peripheral.readRSSI()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) { print(
        "FAILED TO CONNECT:",
        peripheral.name ?? "Unnamed",
        error?.localizedDescription ?? "Unknown error"
    )
        Task { @MainActor in
            clearConnectionState()

            if manualDisconnectRequested {
                connectionMessage = "Not connected"
            } else {
                reconnectPeripheral = peripheral
                scheduleReconnect(to: peripheral)
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            clearConnectionState()

            if manualDisconnectRequested {
                manualDisconnectRequested = false
                reconnectAttempt = 0
                connectionMessage = "Not connected"
            } else {
                reconnectPeripheral = peripheral
                scheduleReconnect(to: peripheral)
            }
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {

    nonisolated func peripheralIsReady(
        toSendWriteWithoutResponse peripheral: CBPeripheral
    ) {
        Task { @MainActor in
            drainRNodeWriteQueue()
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        Task { @MainActor in
            if let error {
                connectionMessage =
                    "Service discovery failed: \(error.localizedDescription)"
                return
            }

            guard let services = peripheral.services else {
                connectionMessage =
                    "Connected, but no BLE services were found"
                return
            }

            serviceCount = services.count
            connectionMessage =
                "Found \(services.count) BLE service(s)"

            for service in services {
                print("RNode service UUID: \(service.uuid)")

                peripheral.discoverCharacteristics(
                    nil,
                    for: service
                )
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                print(
                    "Characteristic discovery error: " +
                    error.localizedDescription
                )
                return
            }

            guard let characteristics =
                    service.characteristics else {
                return
            }

            for characteristic in characteristics {
                print(
                    "Characteristic \(characteristic.uuid), " +
                    "properties: \(characteristic.properties)"
                )

                let uuid =
                    characteristic.uuid.uuidString.uppercased()

                switch uuid {
                case "6E400002-B5A3-F393-E0A9-E50E24DCCA9E":
                    rnodeWriteCharacteristic = characteristic
                    print("Saved RNode write characteristic")

                case "6E400003-B5A3-F393-E0A9-E50E24DCCA9E":
                    rnodeNotifyCharacteristic = characteristic

                    peripheral.setNotifyValue(
                        true,
                        for: characteristic
                    )

                    print("Subscribed to RNode notifications")
                    
                case "2A19":
                    if characteristic.properties.contains(.notify) {
                        peripheral.setNotifyValue(
                            true,
                            for: characteristic
                        )
                    }

                    if characteristic.properties.contains(.read) {
                        peripheral.readValue(
                            for: characteristic
                        )
                    }

                    print("Subscribed to BLE battery updates")
                default:
                    if characteristic.properties.contains(.read) {
                        peripheral.readValue(
                            for: characteristic
                        )
                    }
                }
            }

            if rnodeWriteCharacteristic != nil,
               rnodeNotifyCharacteristic != nil {
                Task { @MainActor in
                    try? await Task.sleep(
                        for: .seconds(1)
                    )
                    guard peripheral.state == .connected else {
                        return
                    }
                    ReticulumCoreBridge.shared
                        .radioDataChannelReady()
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                print(
                    "Notification subscription failed: " +
                    error.localizedDescription
                )
                return
            }

            if characteristic.isNotifying,
               characteristic.uuid ==
                    rnodeNotifyCharacteristic?.uuid {
                connectionMessage = "RNode data channel ready"
                print("RNode notification channel is active")

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.5
                ) {
                    self.requestRNodeDetails()
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                print(
                    "Characteristic read failed: " +
                    error.localizedDescription
                )
                return
            }

            guard let data = characteristic.value else {
                return
            }

            if characteristic.uuid ==
                rnodeNotifyCharacteristic?.uuid {
                bluetoothBytesReceived += data.count
                receivedData.append(data)

                let frames = frameAssembler.append(data)

                for frame in frames {
                    let packet = packetDecoder.decode(frame)
                    print(
                        """
                        RNode decoded command
                        Type: \(packet.commandType)
                        Payload bytes: \(packet.payload.count)
                        """
                    )
                    if packet.commandType == .data {
                        print(
                            "RNode RADIO DATA received: \(packet.payload.count) bytes"
                        )
                        let payloadData = Data(packet.payload)

                        do {
                            let reticulumPacket =
                                try reticulumDecoder.decode(payloadData)
                            print(
                                """
                                ===== RETICULUM PACKET =====
                                Classification: \(reticulumPacket.diagnosticClassification)
                                Packet Type: \(reticulumPacket.packetType)
                                Destination Type: \(reticulumPacket.destinationType)
                                Context: \(reticulumPacket.context.map(String.init(describing:)) ?? "Unknown")
                                Context Raw: 0x\(String(format: "%02X", reticulumPacket.contextRawValue))
                                Destination: \(reticulumPacket.destinationHashHex)
                                Payload Length: \(reticulumPacket.payload.count) bytes
                                ============================
                                """
                            )   

                            reticulumBytesReceived +=
                                reticulumPacket.raw.count
                            lastPacketTime = Date()
                            ReticulumCoreBridge.shared.feed(
                                reticulumPacket.raw
                            )

                            print("Reticulum packet received")
                            print("Destination:", reticulumPacket.destinationHashHex)
                            print("Type:", reticulumPacket.packetType)

                            if reticulumPacket.isAnnounce {
                                print("Announce packet detected")

                                do {
                                    let announce = try announceDecoder.decode(
                                        reticulumPacket
                                    )

                                    let announceID = Data(
                                        SHA256.hash(
                                            data: reticulumPacket.raw
                                        )
                                    )

                                    let linkDestination =
                                        ReticulumCoreBridge.shared
                                            .destinationHash
                                            .lowercased()
                                    guard linkDestination.isEmpty ||
                                            announce.destinationHashHex !=
                                            linkDestination else {
                                        print(
                                            "Ignored local Link-core announce"
                                        )
                                        continue
                                    }

                                    let localPublicKey = try?
                                        ReticulumIdentityStore.shared
                                            .loadIdentity()?.publicKey

                                    let decision =
                                        announceEventTracker.decision(
                                            for: announce,
                                            eventID: announceID,
                                            localPublicKey: localPublicKey
                                        )

                                    guard decision != .ownAnnounce else {
                                        print(
                                            "Ignored local Reticulum announce"
                                        )
                                        continue
                                    }

                                    guard decision != .duplicate else {
                                        print(
                                            "Ignored duplicate Reticulum announce"
                                        )
                                        continue
                                    }

                                    packetsReceived += 1
                                    lastPacketTime = announce.receivedAt

                                    ReticulumAnnounceStore.shared.save(
                                        announce,
                                        eventID: announceID
                                    )

                                    ReticulumDiscoveredPeerStore.shared.discover(
                                        destinationHash: announce.destinationHashHex,
                                        displayName: announce.displayName,
                                        seenAt: announce.receivedAt
                                    )

                                    if !LXMFContactStore.shared.contains(
                                        destinationHash:
                                            announce.destinationHashHex
                                    ) {
                                        AnnouncementNotificationManager.shared.notify(
                                            name: announce.displayName,
                                            destinationHash: announce.destinationHashHex,
                                            eventID: announceID
                                        )
                                    } else {
                                        print(
                                            "Known contact announce updated without nearby notification"
                                        )
                                    }

                                    print(
                                        """
                                        VALID RETICULUM ANNOUNCE RECEIVED
                                        Destination: \(announce.destinationHashHex)
                                        Name: \(announce.displayName ?? "Unknown")
                                        """
                                    )
                                } catch {
                                    print(
                                        "Reticulum announce rejected: " +
                                        error.localizedDescription
                                    )
                                }
                            } else {
                                handleIncomingLXMF(
                                    reticulumPacket
                                )
                            }

                        } catch {
                            print("Not a decoded Reticulum packet:", error)
                        }

                        print(
                            "Radio data received:",
                            payloadData.map {
                                String(format: "%02X", $0)
                            }.joined(separator: " ")
                        )

                        if let text = String(
                            data: payloadData,
                            encoding: .utf8
                        ) {
                            print("Radio data as text: \(text)")
                        }

                        continue
                    }
                    let telemetry = packetRouter.route(packet)

                    if let firmwareVersion = telemetry.firmwareVersion {
                        self.firmwareVersion = firmwareVersion
                    }

                    if let batteryPercent = telemetry.batteryPercent {
                        hasRNodeBatteryTelemetry = true
                        self.batteryPercent = batteryPercent
                        sendLowBatteryNotification(
                            percent: batteryPercent
                        )
                    }

                    if let batteryState = telemetry.batteryState {
                        self.batteryState = batteryState
                    }

                    if let temperature = telemetry.temperature {
                        self.temperature = temperature
                    }

                    if let radioReady = telemetry.radioReady {
                        self.radioReady = radioReady
                    }
                    
                    if let frequency = telemetry.frequency {
                        radioFrequency = frequency
                    }

                    if let bandwidth = telemetry.bandwidth {
                        radioBandwidth = bandwidth
                    }

                    if let transmitPower = telemetry.transmitPower {
                        self.transmitPower = transmitPower
                    }

                    if let spreadingFactor = telemetry.spreadingFactor {
                        self.spreadingFactor = spreadingFactor
                    }

                    if let codingRate = telemetry.codingRate {
                        self.codingRate = codingRate
                    }

                    if let receivedBytes = telemetry.receivedBytes {
                        self.receivedBytes = receivedBytes
                    }

                    if let transmittedBytes = telemetry.transmittedBytes {
                        self.transmittedBytes = transmittedBytes
                    }

                    if let packetRSSI = telemetry.packetRSSI {
                        self.packetRSSI = packetRSSI
                    }

                    if let packetSNR = telemetry.packetSNR {
                        self.packetSNR = packetSNR
                    }

                    if let satelliteCount = telemetry.satelliteCount {
                        self.satelliteCount = satelliteCount
                    }

                    if let uptimeSeconds = telemetry.uptimeSeconds {
                        self.uptimeSeconds = uptimeSeconds
                    }

                    let commandByte = packet.command.map {
                        String(format: "0x%02X", $0)
                    } ?? "Unavailable"

                    print("""
                    Complete RNode frame received
                    Length: \(packet.length) bytes
                    Starts with C0: \(packet.startsWithFrame)
                    Ends with C0: \(packet.endsWithFrame)
                    Command byte: \(commandByte)
                    Raw: \(packet.hexString)
                    """)
                }
                
            } else if characteristic.uuid == CBUUID(string: "2A24") {
                if let text = String(data: data, encoding: .utf8) {
                    print("BLE Model Number String: \(text)")
                    boardName = text == "RAK4640" ? "RAK4631" : text
                }

            } else if characteristic.uuid == CBUUID(string: "2A26") {
                if let text = String(data: data, encoding: .utf8) {
                    print("BLE Firmware Revision: \(text)")
                }

            } else if characteristic.uuid == CBUUID(string: "2A19") {
                if let rawValue = data.first {
                    let reportedLevel = Int(rawValue)
                    print("Battery UUID: \(characteristic.uuid.uuidString)")
                    print("BLE Battery raw byte: \(reportedLevel)")
                    print("BLE Battery data: \(data as NSData)")
                    print("BLE Battery byte count: \(data.count)")

                    if (0...100).contains(reportedLevel),
                       !hasRNodeBatteryTelemetry {
                        batteryPercent = reportedLevel
                        sendLowBatteryNotification(
                            percent: reportedLevel
                        )
                    } else {
                        print(
                            hasRNodeBatteryTelemetry
                                ? "Ignoring BLE battery fallback because RNode telemetry is active"
                                : "Ignoring invalid BLE battery level \(reportedLevel)"
                        )
                    }
                }
            } else if let text = String(
                data: data,
                encoding: .utf8
            ) {
                print(
                    "\(characteristic.uuid): \(text)"
                )
            } else {
                print(
                    "\(characteristic.uuid): \(data as NSData)"
                )
            }
        }
    }
    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                connectionMessage =
                    "RNode write failed: \(error.localizedDescription)"
            } else {
                print("Successfully wrote data to \(characteristic.uuid)"
                )
            }
        }
    }
    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didReadRSSI RSSI: NSNumber,
        error: Error?
    ) {
        guard error == nil else {
            print("RSSI read failed: \(error?.localizedDescription ?? "Unknown error")")
            return
        }

        Task { @MainActor in
            self.lastRSSI = RSSI.intValue
            print("Connected RNode RSSI: \(RSSI.intValue) dBm")
        }
    }

    }
