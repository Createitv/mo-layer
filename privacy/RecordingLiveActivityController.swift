import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

@MainActor
final class RecordingLiveActivityController {
    static let shared = RecordingLiveActivityController()

    private var activity: Activity<RecordingActivityAttributes>?
    private var startedAt: Date?

    private init() {}

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else { return }

        let now = Date()
        let attributes = RecordingActivityAttributes(title: L.string("Recording"))
        let state = RecordingActivityAttributes.ContentState(
            startedAt: now,
            elapsedTime: 0,
            level: 0,
            phase: .recording
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            startedAt = now
        } catch {
            activity = nil
            startedAt = nil
        }
    }

    func update(elapsedTime: TimeInterval, level: CGFloat) {
        guard let activity, let startedAt else { return }
        let state = RecordingActivityAttributes.ContentState(
            startedAt: startedAt,
            elapsedTime: elapsedTime,
            level: min(max(Double(level), 0), 1),
            phase: .recording
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    func markSaving(elapsedTime: TimeInterval, level: CGFloat) {
        updatePhase(.saving, elapsedTime: elapsedTime, level: level)
    }

    func endSaved(elapsedTime: TimeInterval) {
        end(phase: .saved, elapsedTime: elapsedTime)
    }

    func endFailed(elapsedTime: TimeInterval) {
        end(phase: .failed, elapsedTime: elapsedTime)
    }

    func endCancelled() {
        end(phase: .failed, elapsedTime: 0)
    }

    private func updatePhase(_ phase: RecordingActivityPhase, elapsedTime: TimeInterval, level: CGFloat) {
        guard let activity, let startedAt else { return }
        let state = RecordingActivityAttributes.ContentState(
            startedAt: startedAt,
            elapsedTime: elapsedTime,
            level: min(max(Double(level), 0), 1),
            phase: phase
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func end(phase: RecordingActivityPhase, elapsedTime: TimeInterval) {
        guard let activity else { return }
        let startedAt = startedAt ?? Date()
        let state = RecordingActivityAttributes.ContentState(
            startedAt: startedAt,
            elapsedTime: elapsedTime,
            level: 0,
            phase: phase
        )
        self.activity = nil
        self.startedAt = nil
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(3))
            )
        }
    }
}
#else
@MainActor
final class RecordingLiveActivityController {
    static let shared = RecordingLiveActivityController()

    private init() {}

    func start() {}
    func update(elapsedTime: TimeInterval, level: CGFloat) {}
    func markSaving(elapsedTime: TimeInterval, level: CGFloat) {}
    func endSaved(elapsedTime: TimeInterval) {}
    func endFailed(elapsedTime: TimeInterval) {}
    func endCancelled() {}
}
#endif
