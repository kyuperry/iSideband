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
        destinationHash: String
    ) {

        let content =
            UNMutableNotificationContent()

        content.title =
            "New Reticulum Node"

        content.body =
            "\(name ?? "Unknown Node") is nearby."

        content.sound = .default

        let request =
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

        UNUserNotificationCenter.current()
            .add(request)
    }
}
