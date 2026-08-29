import Combine
import Foundation

enum ActivePacketInterface: String, CaseIterable, Identifiable {
    case none
    case bluetoothRNode
    case wifiLocalNetwork
    case raspberryPi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "Off"
        case .bluetoothRNode:
            return "Bluetooth RNode"
        case .wifiLocalNetwork:
            return "Wi-Fi / Local Network"
        case .raspberryPi:
            return "Raspberry Pi / Wi-Fi HaLow"
        }
    }

    var systemImage: String {
        switch self {
        case .none:
            return "antenna.radiowaves.left.and.right.slash"
        case .bluetoothRNode:
            return "antenna.radiowaves.left.and.right"
        case .wifiLocalNetwork:
            return "network"
        case .raspberryPi:
            return "desktopcomputer"
        }
    }
}

@MainActor
final class PacketInterfaceManager: ObservableObject {
    static let shared = PacketInterfaceManager()

    private enum DefaultsKey {
        static let activeInterface = "activePacketInterface"
        static let enabledInterfaces = "enabledPacketInterfaces"
    }

    @Published private(set) var activeInterface: ActivePacketInterface
    /// Interfaces are independent transports and may be enabled together.
    @Published private(set) var enabledInterfaces: Set<ActivePacketInterface>

    private weak var bluetooth: BluetoothManager?

    private init() {
        let savedValue = UserDefaults.standard.string(
            forKey: DefaultsKey.activeInterface
        )
        let saved = ActivePacketInterface(rawValue: savedValue ?? "")
            ?? .bluetoothRNode
        let storedInterfaces = UserDefaults.standard.stringArray(
            forKey: DefaultsKey.enabledInterfaces
        )?.compactMap(ActivePacketInterface.init(rawValue:))
        let initialInterfaces = Set(
            storedInterfaces ?? (saved == .none ? [] : [saved])
        )
        enabledInterfaces = initialInterfaces
        activeInterface = PacketInterfaceManager.preferredInterface(
            in: initialInterfaces
        )
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

    func setEnabled(_ interface: ActivePacketInterface, _ enabled: Bool) {
        var next = enabledInterfaces
        if enabled { next.insert(interface) } else { next.remove(interface) }
        enabledInterfaces = next
        activeInterface = Self.preferredInterface(in: next)
        UserDefaults.standard.set(activeInterface.rawValue, forKey: DefaultsKey.activeInterface)
        UserDefaults.standard.set(
            next.map(\.rawValue).sorted(),
            forKey: DefaultsKey.enabledInterfaces
        )
        enforceSelection()
    }

    func isActive(_ interface: ActivePacketInterface) -> Bool {
        enabledInterfaces.contains(interface)
    }

    private func enforceSelection() {
        if !enabledInterfaces.contains(.wifiLocalNetwork) {
            WiFiLANInterfaceManager.shared.disconnect()
        }
        if !enabledInterfaces.contains(.raspberryPi) {
            PiHaLowInterfaceManager.shared.disconnect()
        }
        if !enabledInterfaces.contains(.bluetoothRNode) {
            bluetooth?.deactivateInterface()
        }
        ReticulumCoreBridge.shared.synchronizeActivePacketInterface()
    }

    private static func preferredInterface(
        in interfaces: Set<ActivePacketInterface>
    ) -> ActivePacketInterface {
        if interfaces.contains(.bluetoothRNode) { return .bluetoothRNode }
        if interfaces.contains(.wifiLocalNetwork) { return .wifiLocalNetwork }
        if interfaces.contains(.raspberryPi) { return .raspberryPi }
        return .none
    }
}

@MainActor
final class WiFiLANInterfaceManager: ObservableObject {
    static let shared = WiFiLANInterfaceManager()

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

    private var connectionTask: Task<Void, Never>?
    private var stateMonitorTask: Task<Void, Never>?

    private init() {}

    func connect(host: String, port: String) {
        guard PacketInterfaceManager.shared.isActive(.wifiLocalNetwork) else {
            state = .failed("Enable Wi-Fi / LAN first")
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

        state = .connecting
        connectionTask = Task { [weak self] in
            let connected = await ReticulumCoreBridge.shared
                .connectWiFiLANAsync(
                    host: cleanedHost,
                    port: portNumber
                )
            guard !Task.isCancelled, let self else { return }
            guard connected else {
                state = .failed(
                    "Reticulum TCP interface could not start"
                )
                return
            }
            startStateMonitoring()
        }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        stateMonitorTask?.cancel()
        stateMonitorTask = nil
        state = .disconnected
        Task {
            await ReticulumCoreBridge.shared.disconnectWiFiLANAsync()
        }
    }

    private func startStateMonitoring() {
        stateMonitorTask?.cancel()
        stateMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let coreState = await ReticulumCoreBridge.shared
                    .wifiLANConnectionStateAsync()
                guard !Task.isCancelled, let self else { return }
                switch coreState {
                case 2:
                    state = .connected
                case 1:
                    state = .connecting
                default:
                    state = .disconnected
                    return
                }
                try? await Task.sleep(for: .milliseconds(750))
            }
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
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .failed(let message): return message
            }
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected

    private var connectionTask: Task<Void, Never>?
    private var stateMonitorTask: Task<Void, Never>?

    private init() {}

    func connect(host: String, port: String) {
        guard PacketInterfaceManager.shared.isActive(.raspberryPi) else {
            state = .failed("Enable Raspberry Pi / Wi-Fi HaLow first")
            return
        }
        disconnect()
        let cleanedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedHost.isEmpty, let portNumber = UInt16(port) else {
            state = .failed("Invalid Raspberry Pi host or port")
            return
        }
        state = .connecting
        connectionTask = Task { [weak self] in
            let connected = await ReticulumCoreBridge.shared
                .connectRaspberryPiAsync(host: cleanedHost, port: portNumber)
            guard !Task.isCancelled, let self else { return }
            guard connected else {
                state = .failed("Raspberry Pi Reticulum interface could not start")
                return
            }
            startStateMonitoring()
        }
    }

    func disconnect() {
        connectionTask?.cancel()
        connectionTask = nil
        stateMonitorTask?.cancel()
        stateMonitorTask = nil
        state = .disconnected
        Task { await ReticulumCoreBridge.shared.disconnectRaspberryPiAsync() }
    }

    private func startStateMonitoring() {
        stateMonitorTask?.cancel()
        stateMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                let coreState = await ReticulumCoreBridge.shared
                    .raspberryPiConnectionStateAsync()
                guard !Task.isCancelled, let self else { return }
                switch coreState {
                case 2: state = .connected
                case 1: state = .connecting
                default:
                    state = .disconnected
                    return
                }
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
    }
}
