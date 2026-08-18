import Combine
import Foundation

enum ActivePacketInterface: String, CaseIterable, Identifiable {
    case none
    case bluetoothRNode
    case raspberryPi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "Off"
        case .bluetoothRNode:
            return "Bluetooth RNode"
        case .raspberryPi:
            return "Raspberry Pi"
        }
    }

    var systemImage: String {
        switch self {
        case .none:
            return "antenna.radiowaves.left.and.right.slash"
        case .bluetoothRNode:
            return "antenna.radiowaves.left.and.right"
        case .raspberryPi:
            return "network"
        }
    }
}

@MainActor
final class PacketInterfaceManager: ObservableObject {
    static let shared = PacketInterfaceManager()

    private enum DefaultsKey {
        static let activeInterface = "activePacketInterface"
    }

    @Published private(set) var activeInterface: ActivePacketInterface

    private weak var bluetooth: BluetoothManager?

    private init() {
        let savedValue = UserDefaults.standard.string(
            forKey: DefaultsKey.activeInterface
        )
        activeInterface = ActivePacketInterface(rawValue: savedValue ?? "")
            ?? .bluetoothRNode
    }

    func configure(bluetooth: BluetoothManager) {
        self.bluetooth = bluetooth
        enforceSelection()
    }

    func select(_ interface: ActivePacketInterface) {
        guard activeInterface != interface else {
            enforceSelection()
            return
        }

        activeInterface = interface
        UserDefaults.standard.set(
            interface.rawValue,
            forKey: DefaultsKey.activeInterface
        )
        enforceSelection()
    }

    func isActive(_ interface: ActivePacketInterface) -> Bool {
        activeInterface == interface
    }

    private func enforceSelection() {
        switch activeInterface {
        case .none:
            PiHaLowInterfaceManager.shared.disconnect()
            bluetooth?.deactivateInterface()

        case .bluetoothRNode:
            PiHaLowInterfaceManager.shared.disconnect()
            ReticulumCoreBridge.shared.synchronizeActivePacketInterface()

        case .raspberryPi:
            bluetooth?.deactivateInterface()
            ReticulumCoreBridge.shared.synchronizeActivePacketInterface()
        }
    }
}

@MainActor
final class PiHaLowInterfaceManager: ObservableObject {
    static let shared = PiHaLowInterfaceManager()

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .disconnected:
                return "Disconnected"
            case .connecting:
                return "Connecting…"
            case .connected:
                return "Connected"
            case .failed(let message):
                return message
            }
        }
    }

    @Published private(set) var state:
        ConnectionState = .disconnected

    private var stateTimer: Timer?

    private init() {}

    func connect(host: String, port: String) {
        guard PacketInterfaceManager.shared.isActive(.raspberryPi) else {
            state = .failed("Select Raspberry Pi as the active interface first")
            return
        }

        disconnect()

        let cleanedHost = host.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanedHost.isEmpty,
              let portNumber = UInt16(port)
        else {
            state = .failed("Invalid host or port")
            return
        }

        guard ReticulumCoreBridge.shared.connectRaspberryPi(
            host: cleanedHost,
            port: portNumber
        ) else {
            state = .failed("Reticulum TCP interface could not start")
            return
        }

        state = .connecting
        startStateMonitoring()
    }

    func disconnect() {
        stateTimer?.invalidate()
        stateTimer = nil
        ReticulumCoreBridge.shared.disconnectRaspberryPi()
        state = .disconnected
    }

    private func startStateMonitoring() {
        stateTimer?.invalidate()
        stateTimer = Timer.scheduledTimer(
            withTimeInterval: 0.75,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch ReticulumCoreBridge.shared
                    .raspberryPiConnectionState {
                case 2:
                    self.state = .connected
                case 1:
                    self.state = .connecting
                default:
                    self.state = .disconnected
                }
            }
        }
        stateTimer?.tolerance = 0.15
    }
}
