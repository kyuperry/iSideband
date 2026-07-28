import Foundation
import UserNotifications

final class AnnouncementNotificationManager {

    static let shared =
        AnnouncementNotificationManager()

    private init() { }

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(
                options: [
                    .alert,
                    .sound,
                    .badge
                ]
            ) { granted, error in

                if let error {
                    print(
                        "Notification permission error:",
                        error
                    )
                }

                print(
                    "Notifications granted:",
                    granted
                )
            }
    }

    func notify(
        name: String?,
        destinationHash: String,
        eventID: Data
    ) {
        guard NotificationPreferences
                .nearbyNodesEnabled else {
            return
        }

        let content =
            UNMutableNotificationContent()

        content.title =
            "New Reticulum Node"

        content.body =
            "\(name ?? "Unknown Node") is nearby."

        if NotificationPreferences.soundsEnabled {
            content.sound = .default
        }
        content.userInfo = [
            "destinationHash": destinationHash
        ]

        let request =
            UNNotificationRequest(
                identifier: eventID.map {
                    String(format: "%02x", $0)
                }.joined(),
                content: content,
                trigger: nil
            )

        UNUserNotificationCenter.current()
            .add(request)
    }
}
