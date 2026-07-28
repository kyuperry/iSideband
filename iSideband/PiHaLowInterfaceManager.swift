import Combine
import Foundation
@preconcurrency import Network

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

    private var connection: NWConnection?

    private init() {}

    func connect(host: String, port: String) {
        disconnect()

        let cleanedHost = host.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanedHost.isEmpty,
              let portNumber = UInt16(port),
              let networkPort = NWEndpoint.Port(
                rawValue: portNumber
              )
        else {
            state = .failed("Invalid host or port")
            return
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(cleanedHost),
            port: networkPort,
            using: .tcp
        )

        self.connection = connection
        state = .connecting

        let manager = self
        let connectionIdentifier =
            ObjectIdentifier(connection)

        connection.stateUpdateHandler = {
            newState in
            Task { @MainActor in
                guard let activeConnection =
                        manager.connection,
                      ObjectIdentifier(
                        activeConnection
                      ) == connectionIdentifier else {
                    return
                }

                switch newState {
                case .ready:
                    manager.state = .connected

                case .failed(let error):
                    manager.state = .failed(
                        error.localizedDescription
                    )
                    manager.connection = nil

                case .cancelled:
                    manager.state = .disconnected
                    manager.connection = nil

                default:
                    break
                }
            }
        }

        connection.start(
            queue: DispatchQueue(
                label: "iSideband.PiHaLowGateway"
            )
        )
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        state = .disconnected
    }
}
