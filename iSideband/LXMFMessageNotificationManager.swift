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
        if !message.content.isEmpty {
            content.body = message.content
        } else if message.attachmentType == .photo {
            content.body = "Photo"
        } else if message.attachmentType == .voiceNote {
            content.body = "Voice message"
        } else if message.attachmentType == .file {
            content.body = "File: \(message.attachmentName ?? "Attachment")"
        } else {
            content.body = "New encrypted message"
        }
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
