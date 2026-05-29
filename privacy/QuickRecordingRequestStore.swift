import Foundation

enum QuickRecordingRequestStore {
    private static let appGroupIdentifier = "group.app.landlady.www.privacy"
    private static let pendingRequestKey = "quickRecording.pendingRequest"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static func requestQuickRecording() {
        defaults.set(true, forKey: pendingRequestKey)
    }

    @discardableResult
    static func consumeQuickRecordingRequest() -> Bool {
        let hasRequest = defaults.bool(forKey: pendingRequestKey)
        if hasRequest {
            defaults.removeObject(forKey: pendingRequestKey)
        }
        return hasRequest
    }
}
