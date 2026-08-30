import Foundation

enum NotificationPreferenceKey {
    static let rnodeConnection = "notifications.rnodeConnection"
    static let nearbyNodes = "notifications.nearbyNodes"
    static let lxmfMessages = "notifications.lxmfMessages"
    static let incomingCalls = "notifications.incomingCalls"
    static let sounds = "notifications.sounds"
}

enum NotificationPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(
            defaults: [
                NotificationPreferenceKey.rnodeConnection: true,
                NotificationPreferenceKey.nearbyNodes: true,
                NotificationPreferenceKey.lxmfMessages: true,
                NotificationPreferenceKey.incomingCalls: true,
                NotificationPreferenceKey.sounds: true
            ]
        )
    }

    static var rnodeConnectionEnabled: Bool {
        UserDefaults.standard.bool(
            forKey: NotificationPreferenceKey.rnodeConnection
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

    static var incomingCallsEnabled: Bool {
        UserDefaults.standard.bool(
            forKey: NotificationPreferenceKey.incomingCalls
        )
    }

    static func batteryEnabled(at _: Int) -> Bool {
        false
    }

    static var soundsEnabled: Bool {
        UserDefaults.standard.bool(
            forKey: NotificationPreferenceKey.sounds
        )
    }
}
