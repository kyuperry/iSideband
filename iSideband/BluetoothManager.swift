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
    @Published private(set) var batteryVoltage: Double?
    @Published private(set) var batteryUpdatedAt: Date?
    @Published private(set) var batteryTelemetrySource: String?
    @Published private(set) var batteryTelemetryAvailable: Bool?
    @Published var radioFrequency: UInt32?
    @Published var radioBandwidth: UInt32?
    @Published var transmitPower: Int?
    @Published var spreadingFactor: Int?
    @Published var codingRate: Int?
    @Published var temperature: Double?
    @Published var radioReady = false
    @Published var radioLocked: Bool?
    @Published var radioErrorMessage: String?
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
    private var notificationConnectedPeripheralID: UUID?
    private var smoothedConnectedRSSI: Double?
    private var rssiTimer: Timer?
    
    private var rnodeWriteCharacteristic: CBCharacteristic?
    private var rnodeNotifyCharacteristic: CBCharacteristic?
    private var batteryLevelCharacteristic: CBCharacteristic?
    private var batteryTelemetryTimer: Timer?
    private var batteryCapabilityTask: Task<Void, Never>?
    private var pendingRNodeWriteChunks: [Data] = []
    private var pendingRNodeWriteHead = 0
    private let maximumPendingRNodeWriteChunks = 4_096
    private let maximumRNodeWritesPerDrain = 32
    private let maximumReceivedDataBytes = 64 * 1_024
    private var appIsActive = true
    private let batteryNotificationMilestones = [50, 25]
    private var sentBatteryMilestones = Set<Int>()
    private var lastBatteryNotificationPercent: Int?
    private var lastRNodeBatteryTelemetryAt: Date?
    private var rnodeBatteryPercent: Int?
    private var bleBatteryPercent: Int?
    private var bleBatteryUpdatedAt: Date?
    private let rnodeBatteryFreshnessInterval: TimeInterval = 15
    private let bleBatteryFreshnessInterval: TimeInterval = 60
    
    override init() {
        super.init()
        
        UNUserNotificationCenter.current().delegate = self
        
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                privacySafeLog(
                    "Notification permission error: " +
                    error.localizedDescription
                )
            } else {
                privacySafeLog("Notification permission granted: \(granted)")
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
        privacySafeLog("Foreground notification delegate called")
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
        guard PacketInterfaceManager.shared.isActive(.bluetoothRNode) else {
            connectionMessage = "Bluetooth RNode interface is not selected"
            return
        }

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
        guard PacketInterfaceManager.shared.isActive(.bluetoothRNode) else {
            connectionMessage = "Bluetooth RNode interface is not selected"
            return
        }

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

    func deactivateInterface() {
        stopScanning()
        let peripheralToCancel =
            connectedPeripheral ?? reconnectPeripheral
        manualDisconnectRequested = true
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        reconnectPeripheral = nil

        if let peripheralToCancel {
            centralManager.cancelPeripheralConnection(peripheralToCancel)
        } else {
            connectingDeviceID = nil
            connectionMessage = "Bluetooth RNode interface disabled"
        }
    }
    
    func sendToRNode(_ data: Data)
    {
        guard PacketInterfaceManager.shared.isActive(.bluetoothRNode) else {
            connectionMessage = "Bluetooth RNode interface is not selected"
            return
        }
        
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

        let requiredChunks = Int(
            ceil(Double(escaped.count) / Double(maximumLength))
        )
        let queuedChunks = pendingRNodeWriteChunks.count -
            pendingRNodeWriteHead
        guard queuedChunks + requiredChunks <=
                maximumPendingRNodeWriteChunks else {
            connectionMessage =
                "RNode is busy — outgoing traffic is being retried"
            privacySafeLog(
                "RNode BLE backpressure rejected a write; queued chunks:",
                queuedChunks
            )
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

    func setAppIsActive(_ isActive: Bool) {
        appIsActive = isActive
        if !isActive {
            reconnectTask?.cancel()
            reconnectTask = nil
            rssiTimer?.invalidate()
            rssiTimer = nil
            batteryTelemetryTimer?.invalidate()
            batteryTelemetryTimer = nil
            batteryCapabilityTask?.cancel()
            batteryCapabilityTask = nil
            return
        }

        guard let connectedPeripheral,
              connectedPeripheral.state == .connected else {
            if let reconnectPeripheral,
               !manualDisconnectRequested {
                scheduleReconnect(to: reconnectPeripheral)
            }
            return
        }
        connectedPeripheral.readRSSI()
        startRSSIPolling(for: connectedPeripheral)
        startBatteryTelemetryPolling()
        drainRNodeWriteQueue()
    }

    private func startRSSIPolling(for peripheral: CBPeripheral) {
        rssiTimer?.invalidate()
        guard appIsActive else {
            rssiTimer = nil
            return
        }
        rssiTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: true
        ) { _ in
            guard peripheral.state == .connected else { return }
            peripheral.readRSSI()
        }
        rssiTimer?.tolerance = 0.25
    }

    private func drainRNodeWriteQueue() {
        guard pendingRNodeWriteHead < pendingRNodeWriteChunks.count,
              let connectedPeripheral,
              let rnodeWriteCharacteristic,
              connectedPeripheral.state == .connected
        else {
            return
        }

        var writesRemaining = maximumRNodeWritesPerDrain
        while writesRemaining > 0,
              connectedPeripheral.canSendWriteWithoutResponse,
              pendingRNodeWriteHead < pendingRNodeWriteChunks.count {
            let chunk = pendingRNodeWriteChunks[pendingRNodeWriteHead]
            pendingRNodeWriteHead += 1
            connectedPeripheral.writeValue(
                chunk,
                for: rnodeWriteCharacteristic,
                type: .withoutResponse
            )
            bluetoothBytesWritten += chunk.count
            writesRemaining -= 1
        }

        if pendingRNodeWriteHead == pendingRNodeWriteChunks.count {
            pendingRNodeWriteChunks.removeAll(keepingCapacity: true)
            pendingRNodeWriteHead = 0
        } else if pendingRNodeWriteHead > 128,
                  pendingRNodeWriteHead * 2 > pendingRNodeWriteChunks.count {
            pendingRNodeWriteChunks.removeFirst(pendingRNodeWriteHead)
            pendingRNodeWriteHead = 0
        }

        if writesRemaining == 0,
           connectedPeripheral.canSendWriteWithoutResponse,
           pendingRNodeWriteHead < pendingRNodeWriteChunks.count {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.drainRNodeWriteQueue()
            }
        }
    }

    var estimatedRadioBitrate: Int32 {
        let defaults = UserDefaults.standard
        let storedBandwidth = defaults.double(
            forKey: "radioBandwidthKHz"
        ) * 1_000
        let bandwidth = Double(radioBandwidth ?? UInt32(storedBandwidth))
        let sf = spreadingFactor ?? defaults.integer(
            forKey: "radioSpreadingFactor"
        )
        let cr = codingRate ?? defaults.integer(
            forKey: "radioCodingRate"
        )
        guard bandwidth > 0, (5...12).contains(sf) else {
            return 5_000
        }
        let codingDenominator = (5...8).contains(cr) ? cr : 5
        let rate = Double(sf) * bandwidth /
            pow(2, Double(sf)) * 4 / Double(codingDenominator)
        return Int32(min(max(rate.rounded(), 300), 50_000))
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
        batteryTelemetryTimer?.invalidate()
        batteryTelemetryTimer = nil
        batteryCapabilityTask?.cancel()
        batteryCapabilityTask = nil

        connectingDeviceID = nil
        connectedDeviceID = nil
        connectedPeripheral = nil
        
        rnodeWriteCharacteristic = nil
        rnodeNotifyCharacteristic = nil
        batteryLevelCharacteristic = nil
        pendingRNodeWriteChunks.removeAll()
        pendingRNodeWriteHead = 0
        batteryPercent = nil
        batteryState = nil
        batteryVoltage = nil
        batteryUpdatedAt = nil
        batteryTelemetrySource = nil
        batteryTelemetryAvailable = nil
        satelliteCount = nil
        uptimeSeconds = nil
        radioReady = false
        radioLocked = nil
        radioErrorMessage = nil
        smoothedConnectedRSSI = nil
        lastRSSI = nil
        lastRNodeBatteryTelemetryAt = nil
        rnodeBatteryPercent = nil
        bleBatteryPercent = nil
        bleBatteryUpdatedAt = nil
        sentBatteryMilestones.removeAll()
        lastBatteryNotificationPercent = nil
        
        serviceCount = 0
    }

    func setRadioConnectionMessage(_ message: String) {
        connectionMessage = message
    }

    private func notifyRNodeConnection(
        name: String,
        isConnected: Bool
    ) {
        guard NotificationPreferences.rnodeConnectionEnabled else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = isConnected
            ? "RNode Connected"
            : "RNode Disconnected"
        content.body = isConnected
            ? "\(name) is connected to iSideband."
            : "\(name) disconnected from iSideband."
        if NotificationPreferences.soundsEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "rnode.connection.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                privacySafeLog(
                    "RNode connection notification failed:",
                    error.localizedDescription
                )
            }
        }
    }

    private func updateConnectedRSSI(_ rawRSSI: Int) {
        let smoothed: Double
        if let previous = smoothedConnectedRSSI {
            // A low-pass filter keeps the reading representative while
            // preventing normal 1 dBm radio noise from jumping categories.
            smoothed = (previous * 0.75) + (Double(rawRSSI) * 0.25)
        } else {
            smoothed = Double(rawRSSI)
        }
        smoothedConnectedRSSI = smoothed

        let rounded = Int(smoothed.rounded())
        guard lastRSSI == nil || abs(rounded - (lastRSSI ?? rounded)) >= 2 else {
            return
        }
        lastRSSI = rounded
    }

    private func notifyRNodeDidConnect(
        id: UUID,
        name: String
    ) {
        guard notificationConnectedPeripheralID != id else {
            return
        }

        notificationConnectedPeripheralID = id
        notifyRNodeConnection(
            name: name,
            isConnected: true
        )
    }

    private func notifyRNodeDidDisconnect(
        id: UUID,
        name: String
    ) {
        guard notificationConnectedPeripheralID == id else {
            return
        }

        notificationConnectedPeripheralID = nil
        notifyRNodeConnection(
            name: name,
            isConnected: false
        )
    }

    private func scheduleReconnect(
        to peripheral: CBPeripheral
    ) {
        guard PacketInterfaceManager.shared.isActive(.bluetoothRNode),
              appIsActive,
              !manualDisconnectRequested,
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
                privacySafeLog(
                    "Low-battery notification skipped: notifications are not authorized"
                )
                return
            }

            do {
                try await center.add(request)
                privacySafeLog("Low-battery notification sent")
            } catch {
                privacySafeLog(
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
            0x06,
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

                privacySafeLog(
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

                privacySafeLog(
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

    private func startBatteryTelemetryPolling() {
        batteryTelemetryTimer?.invalidate()
        batteryCapabilityTask?.cancel()
        batteryTelemetryAvailable = nil
        requestBatteryTelemetry()
        guard appIsActive else { return }
        batteryTelemetryTimer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.requestBatteryTelemetry()
            }
        }
        batteryTelemetryTimer?.tolerance = 3
        batteryCapabilityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled,
                  let self,
                  self.batteryPercent == nil else {
                return
            }
            self.batteryTelemetryAvailable = false
        }
    }

    private func requestBatteryTelemetry() {
        guard connectedDeviceID != nil else { return }
        // RNode firmware publishes CMD_STAT_BAT (0x27) on the serial/BLE
        // channel every few seconds. There is no battery query command, so
        // only explicitly read the standard BLE Battery Service fallback.
        if let connectedPeripheral,
           let batteryLevelCharacteristic,
           batteryLevelCharacteristic.properties.contains(.read) {
            connectedPeripheral.readValue(for: batteryLevelCharacteristic)
        }
    }

    func sendRadioPayload(_ payload: Data) {
        guard !payload.isEmpty else {
            privacySafeLog("Cannot send an empty radio payload")
            return
        }
        guard radioReady else {
            privacySafeLog("Radio payload rejected: RNode LoRa radio is not ready")
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
        
        #if DEBUG
        privacySafeLog(
            "Radio payload handed to RNode: \(payload.count) bytes"
        )
        #endif
    }
    func sendMessage(_ text: String) {
        guard let payload = text.data(using: .utf8) else {
            privacySafeLog("Unable to encode message")
            return
        }
        
        sendRadioPayload(payload)
        
        privacySafeLog("Sent raw radio-data test: \(text)")
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

            privacySafeLog(
                """
                VALID LXMF MESSAGE RECEIVED
                Source: \(message.sourceHashHex)
                Content: \(message.content)
                """
            )
        } catch {
            lastInboundDiagnostic =
                "LXMF rejected: \(error)"
            privacySafeLog(
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
                if let connectedPeripheral {
                    notifyRNodeDidDisconnect(
                        id: connectedPeripheral.identifier,
                        name: connectedDeviceName ??
                            connectedPeripheral.name ?? "RNode"
                    )
                }
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
            guard PacketInterfaceManager.shared.isActive(.bluetoothRNode) else {
                central.cancelPeripheralConnection(peripheral)
                return
            }

            // State restoration can be the app's first callback after iOS
            // launches it in the background. This is intentionally idempotent.
            LXMFManager.shared.start(bluetooth: self)

            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
            manualDisconnectRequested = false
            reconnectPeripheral = peripheral
            connectedPeripheral = peripheral
            smoothedConnectedRSSI = nil
            lastRSSI = nil
            connectedDeviceID = peripheral.identifier
            connectedDeviceName =
                peripheral.name ?? "RNode"
            // Restoration resumes an existing connection rather than
            // creating a new connection transition. Seed the gate so a
            // repeated callback cannot produce a duplicate alert.
            notificationConnectedPeripheralID =
                peripheral.identifier
            connectingDeviceID = nil
            connectionMessage =
                "Restored connection to \(peripheral.name ?? "RNode")"

            peripheral.delegate = self
            peripheral.discoverServices(nil)
            peripheral.readRSSI()

            privacySafeLog(
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
            guard PacketInterfaceManager.shared.isActive(.bluetoothRNode) else {
                return
            }

            let advertisedName =
                advertisementData[
                    CBAdvertisementDataLocalNameKey
                ] as? String

            let name =
                advertisedName ??
                peripheral.name ??
                ""
            privacySafeLog("DISCOVERED:", name.isEmpty ? "Unnamed" : name, peripheral.identifier, RSSI)
            
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
    ) { privacySafeLog("CONNECTED TO:", peripheral.name ?? "Unnamed", peripheral.identifier)
        Task { @MainActor in
            guard PacketInterfaceManager.shared.isActive(.bluetoothRNode) else {
                central.cancelPeripheralConnection(peripheral)
                return
            }

            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
            manualDisconnectRequested = false
            reconnectPeripheral = peripheral
            connectedPeripheral = peripheral
            smoothedConnectedRSSI = nil
            lastRSSI = nil
            connectingDeviceID = nil
            connectedDeviceID = peripheral.identifier
            connectedDeviceName =
                peripheral.name ?? "RNode"

            connectionMessage =
                "Connected to \(peripheral.name ?? "RNode")"

            notifyRNodeDidConnect(
                id: peripheral.identifier,
                name: peripheral.name ?? "RNode"
            )

            peripheral.delegate = self
            peripheral.discoverServices(nil)
            peripheral.readRSSI()

            startRSSIPolling(for: peripheral)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) { privacySafeLog(
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
            guard connectedPeripheral?.identifier ==
                    peripheral.identifier else {
                return
            }

            let disconnectedName =
                connectedDeviceName ?? peripheral.name ?? "RNode"

            notifyRNodeDidDisconnect(
                id: peripheral.identifier,
                name: disconnectedName
            )
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
                privacySafeLog("RNode service UUID: \(service.uuid)")

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
                privacySafeLog(
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
                privacySafeLog(
                    "Characteristic \(characteristic.uuid), " +
                    "properties: \(characteristic.properties)"
                )

                let uuid =
                    characteristic.uuid.uuidString.uppercased()

                switch uuid {
                case "6E400002-B5A3-F393-E0A9-E50E24DCCA9E":
                    rnodeWriteCharacteristic = characteristic
                    privacySafeLog("Saved RNode write characteristic")

                case "6E400003-B5A3-F393-E0A9-E50E24DCCA9E":
                    rnodeNotifyCharacteristic = characteristic

                    peripheral.setNotifyValue(
                        true,
                        for: characteristic
                    )

                    privacySafeLog("Subscribed to RNode notifications")
                    
                case "2A19":
                    batteryLevelCharacteristic = characteristic
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

                    privacySafeLog("Subscribed to BLE battery updates")
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
                startBatteryTelemetryPolling()
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
                privacySafeLog(
                    "Notification subscription failed: " +
                    error.localizedDescription
                )
                return
            }

            if characteristic.isNotifying,
               characteristic.uuid ==
                    rnodeNotifyCharacteristic?.uuid {
                connectionMessage = "RNode data channel ready"
                privacySafeLog("RNode notification channel is active")

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
                privacySafeLog(
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
                if receivedData.count > maximumReceivedDataBytes * 2 {
                    receivedData = Data(
                        receivedData.suffix(maximumReceivedDataBytes)
                    )
                }

                let frames = frameAssembler.append(data)

                for frame in frames {
                    let packet = packetDecoder.decode(frame)
                    if packet.commandType == .batteryState {
                        privacySafeLog("RNode battery frame received:", packet.payload.map { String(format: "%02X", $0) }.joined(separator: " "))
                    }
                    privacySafeLog(
                        """
                        RNode decoded command
                        Type: \(packet.commandType)
                        Payload bytes: \(packet.payload.count)
                        """
                    )
                    if packet.commandType == .data {
                        privacySafeLog(
                            "RNode RADIO DATA received: \(packet.payload.count) bytes"
                        )
                        let payloadData = Data(packet.payload)

                        do {
                            let reticulumPacket =
                                try reticulumDecoder.decode(payloadData)
                            privacySafeLog(
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

                            privacySafeLog("Reticulum packet received")
                            privacySafeLog("Destination:", reticulumPacket.destinationHashHex)
                            privacySafeLog("Type:", reticulumPacket.packetType)

                            if reticulumPacket.isAnnounce {
                                privacySafeLog("Announce packet detected")

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
                                        privacySafeLog(
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
                                        privacySafeLog(
                                            "Ignored local Reticulum announce"
                                        )
                                        continue
                                    }

                                    guard decision != .duplicate else {
                                        // A repeated announce can carry the identity
                                        // needed by LXST even when the packet tracker
                                        // suppresses the notification.
                                        ReticulumDiscoveredPeerStore.shared.discover(
                                            destinationHash: announce.destinationHashHex,
                                            identityHash: announce.identityHashHex,
                                            displayName: announce.displayName,
                                            announcedHops: reticulumPacket.hops,
                                            seenAt: announce.receivedAt
                                        )
                                        privacySafeLog(
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
                                        identityHash: announce.identityHashHex,
                                        displayName: announce.displayName,
                                        announcedHops: reticulumPacket.hops,
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
                                        privacySafeLog(
                                            "Known contact announce updated without nearby notification"
                                        )
                                    }

                                    privacySafeLog(
                                        """
                                        VALID RETICULUM ANNOUNCE RECEIVED
                                        Destination: \(announce.destinationHashHex)
                                        Name: \(announce.displayName ?? "Unknown")
                                        """
                                    )
                                } catch {
                                    privacySafeLog(
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
                            privacySafeLog("Not a decoded Reticulum packet:", error)
                        }

                        privacySafeLog(
                            "Radio data received:",
                            payloadData.map {
                                String(format: "%02X", $0)
                            }.joined(separator: " ")
                        )

                        if let text = String(
                            data: payloadData,
                            encoding: .utf8
                        ) {
                            privacySafeLog("Radio data as text: \(text)")
                        }

                        continue
                    }
                    let telemetry = packetRouter.route(packet)

                    if let firmwareVersion = telemetry.firmwareVersion {
                        self.firmwareVersion = firmwareVersion
                    }

                    if let batteryPercent = telemetry.batteryPercent {
                        let now = Date()
                        lastRNodeBatteryTelemetryAt = now
                        // The firmware already averages its ADC samples before
                        // encoding this integer. Preserve that exact value.
                        rnodeBatteryPercent = batteryPercent
                        privacySafeLog("RNode battery telemetry received: \(batteryPercent)%")
                        reconcileBatteryReadings(updatedAt: now)
                    }

                    if let batteryState = telemetry.batteryState {
                        self.batteryState = batteryState
                        if telemetry.batteryPercent == nil {
                            batteryUpdatedAt = Date()
                        }
                    }

                    if let batteryVoltage = telemetry.batteryVoltage {
                        self.batteryVoltage = batteryVoltage
                    }

                    if let temperature = telemetry.temperature {
                        self.temperature = temperature
                    }

                    if let radioReady = telemetry.radioReady {
                        self.radioReady = radioReady
                        privacySafeLog(
                            radioReady
                                ? "RNode LoRa radio is ON"
                                : "RNode LoRa radio is OFF"
                        )
                    }

                    if let radioLocked = telemetry.radioLocked {
                        self.radioLocked = radioLocked
                        privacySafeLog("RNode radio lock: \(radioLocked)")
                    }

                    if let errorCode = telemetry.errorCode {
                        let message = Self.rnodeErrorMessage(
                            for: errorCode
                        )
                        radioErrorMessage = message
                        radioReady = false
                        privacySafeLog(
                            "RNode firmware error 0x" +
                            String(format: "%02X", errorCode) +
                            ": " + message
                        )
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

                    privacySafeLog("""
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
                    privacySafeLog("BLE Model Number String: \(text)")
                    boardName = text == "RAK4640" ? "RAK4631" : text
                }

            } else if characteristic.uuid == CBUUID(string: "2A26") {
                if let text = String(data: data, encoding: .utf8) {
                    privacySafeLog("BLE Firmware Revision: \(text)")
                }

            } else if characteristic.uuid == CBUUID(string: "2A19") {
                if let rawValue = data.first {
                    let reportedLevel = Int(rawValue)
                    privacySafeLog("Battery UUID: \(characteristic.uuid.uuidString)")
                    privacySafeLog("BLE Battery raw byte: \(reportedLevel)")
                    privacySafeLog("BLE Battery data: \(data as NSData)")
                    privacySafeLog("BLE Battery byte count: \(data.count)")

                    // Some RNode firmware revisions expose their calculated
                    // percentage on the standard BLE Battery Level
                    // characteristic before applying the final 100% cap.
                    // Reticulum applies the same cap to CMD_STAT_BAT. Preserve
                    // 0xFF as the BLE "unknown" sentinel instead of treating
                    // it as a full battery.
                    if let normalizedLevel =
                        RNodePacketRouter.decodeBLEBatteryPercent(rawValue) {
                        let now = Date()
                        bleBatteryPercent = normalizedLevel
                        bleBatteryUpdatedAt = now
                        reconcileBatteryReadings(updatedAt: now)
                    } else {
                        privacySafeLog(
                            "Ignoring unknown BLE battery level"
                        )
                    }
                }
            } else if let text = String(
                data: data,
                encoding: .utf8
            ) {
                privacySafeLog(
                    "\(characteristic.uuid): \(text)"
                )
            } else {
                privacySafeLog(
                    "\(characteristic.uuid): \(data as NSData)"
                )
            }
        }
    }

    private func reconcileBatteryReadings(updatedAt: Date) {
        let now = Date()
        let nativeFresh = rnodeBatteryPercent != nil &&
            lastRNodeBatteryTelemetryAt.map {
                now.timeIntervalSince($0) <=
                    rnodeBatteryFreshnessInterval
            } == true
        let bleFresh = bleBatteryPercent != nil &&
            bleBatteryUpdatedAt.map {
                now.timeIntervalSince($0) <=
                    bleBatteryFreshnessInterval
            } == true

        let candidate: Int
        let source: String
        if nativeFresh, let native = rnodeBatteryPercent {
            // CMD_STAT_BAT is generated from the firmware's own filtered
            // battery_percent value and is authoritative when available.
            candidate = native
            source = "RNode firmware"
        } else if bleFresh, let ble = bleBatteryPercent {
            candidate = ble
            source = "BLE Battery Service"
            // The standard Battery Level characteristic carries no charging
            // state. Do not retain a stale state from an older RNode frame.
            batteryState = nil
        } else {
            return
        }

        let clamped = min(max(candidate, 0), 100)
        guard batteryPercent == nil ||
                clamped != batteryPercent else {
            batteryUpdatedAt = updatedAt
            batteryTelemetrySource = source
            batteryTelemetryAvailable = true
            return
        }
        batteryPercent = clamped
        batteryUpdatedAt = updatedAt
        batteryTelemetrySource = source
        batteryTelemetryAvailable = true
        sendLowBatteryNotification(percent: clamped)
    }

    private static func rnodeErrorMessage(for code: UInt8) -> String {
        switch code {
        case 0x01:
            return "The RNode could not initialize its LoRa radio."
        case 0x02:
            return "The RNode radio transmission failed."
        case 0x03:
            return "The RNode configuration storage is locked."
        case 0x04:
            return "The RNode transmit queue is full."
        case 0x05:
            return "The RNode is low on memory."
        case 0x06:
            return "The RNode modem timed out."
        default:
            return "The RNode reported an unknown radio error."
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
                privacySafeLog("Successfully wrote data to \(characteristic.uuid)"
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
            privacySafeLog("RSSI read failed: \(error?.localizedDescription ?? "Unknown error")")
            return
        }

        Task { @MainActor in
            self.updateConnectedRSSI(RSSI.intValue)
            privacySafeLog("Connected RNode RSSI: \(RSSI.intValue) dBm")
        }
    }

    }
