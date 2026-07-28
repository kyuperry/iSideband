import Foundation

enum NotificationPreferenceKey {
    static let nearbyNodes = "notifications.nearbyNodes"
    static let lxmfMessages = "notifications.lxmfMessages"
    static let battery50 = "notifications.battery50"
    static let battery25 = "notifications.battery25"
    static let sounds = "notifications.sounds"
}

enum NotificationPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(
            defaults: [
                NotificationPreferenceKey.nearbyNodes: true,
                NotificationPreferenceKey.lxmfMessages: true,
                NotificationPreferenceKey.battery50: true,
                NotificationPreferenceKey.battery25: true,
                NotificationPreferenceKey.sounds: true
            ]
        )
    }

    static var nearbyNodesEnabled: Bool {
        UserDefaults.standard.bool(
            forKey: NotificationPreferenceKey.nearbyNodes
        )
    }

    static var lxmfMessagesEnabled: Bool {
        UserDefaults.standard.bool(
            forKey: NotificationPreferenceKey.lxmfMessages
        )
    }

    static func batteryEnabled(at milestone: Int) -> Bool {
        let key: String

        switch milestone {
        case 50:
            key = NotificationPreferenceKey.battery50
        case 25:
            key = NotificationPreferenceKey.battery25
        default:
            return false
        }

        return UserDefaults.standard.bool(forKey: key)
    }

    static var soundsEnabled: Bool {
        UserDefaults.standard.bool(
            forKey: NotificationPreferenceKey.sounds
        )
    }
}
