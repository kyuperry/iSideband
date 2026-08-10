import ActivityKit
import Foundation

struct RNodeLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var reticulumBytesIn: Int
        var reticulumBytesOut: Int
        var uptimeStartedAt: Date
        var isReticulumAvailable: Bool
    }

    var rnodeName: String
}
