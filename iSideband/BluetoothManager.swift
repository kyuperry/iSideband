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

    private static let uartService = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let uartWrite = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private static let uartNotify = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

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
        guard connectingDeviceID == nil, connectedPeripheral == nil else {
            return
        }

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
            let rnodeWriteCharacteristic,
            rnodeNotifyCharacteristic?.isNotifying == true
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

            let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let names = [advertisedName, peripheral.name].compactMap { $0 }
            let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
            let overflowUUIDs = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
            let hasKnownName = names.contains {
                $0.localizedCaseInsensitiveContains("RNode") ||
                $0.localizedCaseInsensitiveContains("Heltec")
            }

            guard hasKnownName ||
                    serviceUUIDs.contains(Self.uartService) ||
                    overflowUUIDs.contains(Self.uartService) else {
                return
            }

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
            guard connectedPeripheral === peripheral else {
                return
            }

            if let error {
                connectionMessage =
                    "Service discovery failed: \(error.localizedDescription)"
                return
            }

            let services = peripheral.services ?? []
            serviceCount = services.count

            guard let service = services.first(where: { $0.uuid == Self.uartService }) else {
                connectionMessage = "RNode Bluetooth service unavailable. Check the board firmware."
                return
            }

            connectionMessage = "Checking RNode data channel…"
            peripheral.discoverCharacteristics([Self.uartWrite, Self.uartNotify], for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            guard connectedPeripheral === peripheral, service.uuid == Self.uartService else {
                return
            }

            if let error {
                connectionMessage = "RNode characteristic discovery failed: \(error.localizedDescription)"
                return
            }

            let characteristics = service.characteristics ?? []
            guard
                let write = characteristics.first(where: {
                    $0.uuid == Self.uartWrite &&
                    ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse))
                }),
                let notify = characteristics.first(where: {
                    $0.uuid == Self.uartNotify &&
                    ($0.properties.contains(.notify) || $0.properties.contains(.indicate))
                })
            else {
                connectionMessage = "RNode data channel unavailable"
                return
            }

            rnodeWriteCharacteristic = write
            rnodeNotifyCharacteristic = notify
            peripheral.setNotifyValue(true, for: notify)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            guard connectedPeripheral === peripheral,
                  characteristic === rnodeNotifyCharacteristic else {
                return
            }

            if let error {
                connectionMessage = "RNode notification subscription failed: \(error.localizedDescription)"
            } else {
                connectionMessage = characteristic.isNotifying
                    ? "RNode data channel ready"
                    : "RNode data channel unavailable"
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            guard connectedPeripheral === peripheral,
                  characteristic === rnodeNotifyCharacteristic else {
                return
            }

            if let error {
                print("RNode notification failed: \(error.localizedDescription)")
                return
            }

            if let data = characteristic.value {
                receivedData.append(data)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            guard connectedPeripheral === peripheral,
                  characteristic === rnodeWriteCharacteristic else {
                return
            }

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
