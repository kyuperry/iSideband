import ActivityKit
import Combine
import Foundation

@MainActor
final class RNodeLiveActivityManager {
    enum ToggleResult {
        case started
        case stopped
        case unavailable
    }

    static let shared = RNodeLiveActivityManager()

    private weak var bluetooth: BluetoothManager?
    private var observation: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
    private var appIsActive = false
    private var connectionStartedAt: Date?
    private var userAllowsActivity = true

    private init() {}

    func configure(bluetooth: BluetoothManager) {
        guard self.bluetooth !== bluetooth else { return }
        self.bluetooth = bluetooth
        observation = bluetooth.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        scheduleRefresh()
    }

    func setAppIsActive(_ isActive: Bool) {
        appIsActive = isActive
        scheduleRefresh(immediately: true)
    }

    func toggle() -> ToggleResult {
        if !Activity<RNodeLiveActivityAttributes>.activities.isEmpty {
            userAllowsActivity = false
            refreshTask?.cancel()
            refreshTask = nil
            let finalStart = connectionStartedAt ?? Date()
            Task { await endActivities(uptimeStartedAt: finalStart) }
            return .stopped
        }

        guard appIsActive,
              bluetooth?.connectedDeviceID != nil,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .unavailable
        }

        userAllowsActivity = true
        scheduleRefresh(immediately: true)
        return .started
    }

    private func scheduleRefresh(immediately: Bool = false) {
        if immediately {
            refreshTask?.cancel()
        } else if refreshTask != nil {
            return
        }

        refreshTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(750))
            }
            guard !Task.isCancelled else { return }
            await self?.refresh()
            self?.refreshTask = nil
        }
    }

    private func refresh() async {
        guard let bluetooth else { return }
        guard bluetooth.connectedDeviceID != nil else {
            let finalStart = connectionStartedAt ?? Date()
            connectionStartedAt = nil
            userAllowsActivity = true
            await endActivities(uptimeStartedAt: finalStart)
            return
        }

        guard userAllowsActivity else {
            return
        }

        if connectionStartedAt == nil { connectionStartedAt = Date() }
        let state = RNodeLiveActivityAttributes.ContentState(
            reticulumBytesIn: bluetooth.reticulumBytesReceived,
            reticulumBytesOut: bluetooth.reticulumBytesTransmitted,
            uptimeStartedAt: uptimeStartDate(for: bluetooth),
            isReticulumAvailable: bluetooth.radioReady
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(30)
        )

        if let activity = Activity<RNodeLiveActivityAttributes>.activities.first {
            await activity.update(content)
        } else if appIsActive && ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                _ = try Activity.request(
                    attributes: RNodeLiveActivityAttributes(
                        rnodeName: bluetooth.connectedDeviceName ?? "RNode"
                    ),
                    content: content,
                    pushType: nil
                )
            } catch {
                print("RNode Live Activity could not start:", error.localizedDescription)
            }
        }
    }

    private func uptimeStartDate(for bluetooth: BluetoothManager) -> Date {
        if let uptime = bluetooth.uptimeSeconds {
            return Date().addingTimeInterval(-Double(uptime))
        }
        return connectionStartedAt ?? Date()
    }

    private func endActivities(uptimeStartedAt: Date) async {
        let finalContent = ActivityContent(
            state: RNodeLiveActivityAttributes.ContentState(
                reticulumBytesIn: bluetooth?.reticulumBytesReceived ?? 0,
                reticulumBytesOut: bluetooth?.reticulumBytesTransmitted ?? 0,
                uptimeStartedAt: uptimeStartedAt,
                isReticulumAvailable: false
            ),
            staleDate: nil
        )
        for activity in Activity<RNodeLiveActivityAttributes>.activities {
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
    }
}
