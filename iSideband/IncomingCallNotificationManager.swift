import Foundation
import UserNotifications

final class IncomingCallNotificationManager {
    static let shared = IncomingCallNotificationManager()

    private let identifier = "lxst.incoming-call"

    private init() {}

    func notify(peer: LXMFPeer) {
        guard NotificationPreferences.incomingCallsEnabled else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Incoming iSideband Call"
        content.body = "Call from \(peer.displayName)"
        content.categoryIdentifier = "LXST_INCOMING_CALL"
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "incomingCall": true,
            "callerHash": peer.destinationHash
        ]
        if NotificationPreferences.soundsEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                privacySafeLog(
                    "Incoming call notification failed:",
                    error.localizedDescription
                )
            }
        }
    }

    func clear() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )
        center.removeDeliveredNotifications(
            withIdentifiers: [identifier]
        )
    }
}
