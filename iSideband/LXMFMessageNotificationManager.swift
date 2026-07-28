import Foundation
import UserNotifications

final class LXMFMessageNotificationManager {
    static let shared =
        LXMFMessageNotificationManager()

    private init() {}

    func notify(
        message: LXMFIncomingMessage,
        senderName: String?
    ) {
        guard NotificationPreferences
                .lxmfMessagesEnabled else {
            return
        }

        let content =
            UNMutableNotificationContent()
        content.title =
            senderName ?? "New LXMF Message"
        content.body = message.content
        if NotificationPreferences.soundsEnabled {
            content.sound = .default
        }
        content.userInfo = [
            "sourceHash": message.sourceHashHex
        ]

        let identifier = message.id.map {
            String(format: "%02x", $0)
        }.joined()
        let request = UNNotificationRequest(
            identifier: "lxmf." + identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current()
            .add(request) { error in
                if let error {
                    print(
                        "LXMF notification failed:",
                        error.localizedDescription
                    )
                }
            }
    }
}
