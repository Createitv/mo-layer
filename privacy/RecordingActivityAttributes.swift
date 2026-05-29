import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var elapsedTime: TimeInterval
        var level: Double
        var phase: RecordingActivityPhase
    }

    var title: String
}

enum RecordingActivityPhase: String, Codable, Hashable {
    case recording
    case saving
    case saved
    case failed
}
