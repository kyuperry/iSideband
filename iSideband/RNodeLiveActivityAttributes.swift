import ActivityKit
import Foundation

struct RNodeLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var reticulumBytesIn: Int
        var reticulumBytesOut: Int
        var uptimeStartedAt: Date
        var isReticulumAvailable: Bool
        var bluetoothRSSI: Int?
        var bluetoothSignalLevel: Int?
        var bluetoothSignalQuality: String?
    }

    var rnodeName: String
}
