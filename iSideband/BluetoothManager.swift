import Foundation
@preconcurrency import CoreBluetooth
import Combine

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
}

@MainActor
final class BluetoothManager: NSObject, ObservableObject {

    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothState: CBManagerState = .unknown

    @Published private(set) var connectedDeviceID: UUID?
    @Published private(set) var connectingDeviceID: UUID?
    @Published private(set) var connectionMessage = "Not connected"

    @Published private(set) var serviceCount = 0
    @Published private(set) var receivedData = Data()
    @Published var packetsReceived = 0
    @Published var lastPacketTime: Date?
    @Published var lastRSSI: Int?

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?

    private var rnodeWriteCharacteristic: CBCharacteristic?
    private var rnodeNotifyCharacteristic: CBCharacteristic?

    override init() {
        super.init()

        centralManager = CBCentralManager(
            delegate: self,
            queue: nil
        )
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

    func sendToRNode(_ data: Data) {
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

            let name = peripheral.name ?? ""

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
    ) {
        Task { @MainActor in
            connectedPeripheral = peripheral
            connectingDeviceID = nil
            connectedDeviceID = peripheral.identifier

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
    ) {
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

                case "6E400003-B5A3-F393-E0A9-E50E24DCCA9E":
                    rnodeNotifyCharacteristic = characteristic

                    peripheral.setNotifyValue(
                        true,
                        for: characteristic
                    )

                    print("Subscribed to RNode notifications")

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
                packetsReceived += 1
                lastPacketTime = Date()
                let packet = RNodePacket(raw: data)

                let commandByte = packet.command.map {
                    String(format: "0x%02X", $0)
                } ?? "Unavailable"

                print("""
                RNode packet received
                Length: \(packet.length) bytes
                Starts with C0: \(packet.startsWithFrame)
                Ends with C0: \(packet.endsWithFrame)
                Command/type byte: \(commandByte)
                Raw: \(packet.hexString)
                """)

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
