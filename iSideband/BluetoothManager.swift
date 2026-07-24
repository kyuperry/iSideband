import Foundation
@preconcurrency import CoreBluetooth
import Combine
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
    @Published var radioFrequency: UInt32?
    @Published var radioBandwidth: UInt32?
    @Published var transmitPower: Int?
    @Published var spreadingFactor: Int?
    @Published var codingRate: Int?
    @Published var temperature: Double?
    @Published var radioReady = false

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?

    private var rnodeWriteCharacteristic: CBCharacteristic?
    private var rnodeNotifyCharacteristic: CBCharacteristic?
    private var hasSentLowBatteryNotification = false

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
            queue: nil
        )
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

        let writeType: CBCharacteristicWriteType =
            rnodeWriteCharacteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse

        connectedPeripheral.writeValue(
            data,
            for: rnodeWriteCharacteristic,
            type: writeType
        )
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
        connectingDeviceID = nil
        connectedDeviceID = nil
        connectedPeripheral = nil

        rnodeWriteCharacteristic = nil
        rnodeNotifyCharacteristic = nil

        serviceCount = 0
    }
    private func sendLowBatteryNotification(percent: Int) {
        guard percent <= 20 else {
            hasSentLowBatteryNotification = false
            return
        }

        guard !hasSentLowBatteryNotification else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "RNode Battery Low"
        content.body = "Your connected RNode battery is at \(percent)%."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "rnode-low-battery",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print(
                    "Low-battery notification failed: " +
                    error.localizedDescription
                )
            } else {
                print("Low-battery notification sent")
            }
        }

        hasSentLowBatteryNotification = true
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
        let frames: [Data] = [
            Data([
                0xC0,
                0x01,
                0x00, 0x00, 0x00, 0x00,
                0xC0
            ]),
            Data([
                0xC0,
                0x02,
                0x00, 0x00, 0x00, 0x00,
                0xC0
            ]),
            Data([
                0xC0,
                0x03,
                0xFF,
                0xC0
            ]),
            Data([
                0xC0,
                0x04,
                0xFF,
                0xC0
            ]),
            Data([
                0xC0,
                0x05,
                0xFF,
                0xC0
            ]),
            Data([
                0xC0,
                0x50,
                0xFF,
                0xC0
            ])
        ]

        for (index, frame) in frames.enumerated() {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (Double(index) * 0.2)
            ) {
                self.sendToRNode(frame)
            }
        }
    }

        func sendMessage(_ text: String) {
        print("Sending message: \(text)")
    }
}

extension BluetoothManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(
        _ central: CBCentralManager
    ) {
        Task { @MainActor in
            bluetoothState = central.state

            if central.state != .poweredOn {
                devices.removeAll()
                isScanning = false
                clearConnectionState()
                connectionMessage = "Bluetooth unavailable"
            } else if connectedDeviceID == nil {
                connectionMessage = "Bluetooth ready"
            }
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
            connectedPeripheral = peripheral
            connectingDeviceID = nil
            connectedDeviceID = peripheral.identifier
            connectedDeviceName =
                peripheral.name ?? "RNode"

            connectionMessage =
                "Connected to \(peripheral.name ?? "RNode")"

            peripheral.delegate = self
            peripheral.discoverServices(nil)
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

            connectionMessage =
                error?.localizedDescription ??
                "Connection failed"
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            clearConnectionState()

            if let error {
                connectionMessage =
                    "Disconnected: \(error.localizedDescription)"
            } else {
                connectionMessage = "Not connected"
            }
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {

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

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.requestRNodeDetails()
                    }

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

            if characteristic.isNotifying {
                connectionMessage = "RNode data channel ready"
                print("RNode notification channel is active")
                
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
                receivedData.append(data)

                let frames = frameAssembler.append(data)

                for frame in frames {
                    packetsReceived += 1
                    lastPacketTime = Date()

                    let packet = packetDecoder.decode(frame)
                    let telemetry = packetRouter.route(packet)

                    if let firmwareVersion = telemetry.firmwareVersion {
                        self.firmwareVersion = firmwareVersion
                    }

                    if let batteryPercent = telemetry.batteryPercent {
                        self.batteryPercent = batteryPercent
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

                    let commandByte = packet.command.map {
                        String(format: "0x%02X", $0)
                    } ?? "Unavailable"

                    print("""
                    Complete RNode frame received
                    Length: \(packet.length) bytes
                    Starts with C0: \(packet.startsWithFrame)
                    Ends with C0: \(packet.endsWithFrame)
                    print("Command byte: \(commandByte)")
                    Raw: \(packet.hexString)
                    """)
                }
                
            } else if characteristic.uuid == CBUUID(string: "2A24") {
                if let text = String(data: data, encoding: .utf8) {
                    print("BLE Model Number String: \(text)")
                    boardName = text
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

                    if reportedLevel <= 100 {
                        batteryPercent = reportedLevel
                        sendLowBatteryNotification(percent: reportedLevel)
                    } else {
                        let cappedLevel = min(reportedLevel, 100)
                        print("Capping BLE battery level \(reportedLevel) to \(cappedLevel)")
                        batteryPercent = cappedLevel
                        sendLowBatteryNotification(percent: cappedLevel)
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
                print(
                    "Successfully wrote data to \(characteristic.uuid)"
                )
            }
        }
    }
    
}
