import Combine
import Foundation

/// Periodically announces the local LXMF delivery destination while the app
/// continues listening for normal Reticulum announces over the connected RNode.
///
/// This mode is intentionally session-only and defaults to off. It never changes
/// radio parameters and it does not run a tight transmit loop.
@MainActor
final class LXMFDiscoveryMode: ObservableObject {
    static let shared = LXMFDiscoveryMode()

    @Published private(set) var isEnabled = false
    @Published private(set) var lastAnnouncedAt: Date?
    @Published private(set) var statusText = "Off"

    private weak var bluetooth: BluetoothManager?
    private weak var manager: LXMFManager?
    private var connectionObservation: AnyCancellable?
    private var announceTask: Task<Void, Never>?

    private let announceInterval: Duration = .seconds(10 * 60)

    private init() { }

    func configure(
        manager: LXMFManager,
        bluetooth: BluetoothManager
    ) {
        self.manager = manager
        self.bluetooth = bluetooth

        connectionObservation = bluetooth
            .$connectedDeviceID
            .removeDuplicates()
            .sink { [weak self] connectedDeviceID in
                guard let self, self.isEnabled else {
                    return
                }

                if connectedDeviceID == nil {
                    self.statusText = "Waiting for RNode"
                } else {
                    self.scheduleAnnounces(sendImmediately: true)
                }
            }
    }

    func start() {
        guard !isEnabled else {
            return
        }

        isEnabled = true
        scheduleAnnounces(sendImmediately: true)
    }

    func stop() {
        isEnabled = false
        announceTask?.cancel()
        announceTask = nil
        statusText = "Off"
    }

    private func scheduleAnnounces(
        sendImmediately: Bool
    ) {
        announceTask?.cancel()

        guard bluetooth?.connectedDeviceID != nil else {
            statusText = "Waiting for RNode"
            return
        }

        statusText = "Listening and announcing"

        announceTask = Task { [weak self] in
            guard let self else {
                return
            }

            if sendImmediately {
                self.sendAnnounce()
            }

            while !Task.isCancelled {
                try? await Task.sleep(
                    for: self.announceInterval
                )

                guard !Task.isCancelled else {
                    return
                }

                guard self.bluetooth?.connectedDeviceID != nil else {
                    self.statusText = "Waiting for RNode"
                    return
                }

                self.sendAnnounce()
            }
        }
    }

    private func sendAnnounce() {
        guard let manager,
              bluetooth?.connectedDeviceID != nil else {
            statusText = "Waiting for RNode"
            return
        }

        manager.announceIdentity()
        lastAnnouncedAt = Date()
        statusText = "Listening and announcing"
    }
}
