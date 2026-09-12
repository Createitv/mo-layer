import Foundation
import UserNotifications

enum PlatformProgressNotificationEvent: Equatable {
    case completed(count: Int)
    case needsAttention(completed: Int, total: Int)
}

enum PlatformProgressNotificationPolicy {
    static func event(completed: Int, total: Int, failedCount: Int) -> PlatformProgressNotificationEvent {
        failedCount == 0 && completed == total
            ? .completed(count: completed)
            : .needsAttention(completed: completed, total: total)
    }

    static func terminalEvent(
        journal: PhotoTransferJournal,
        cancelled: Bool,
        hasError: Bool
    ) -> PlatformProgressNotificationEvent? {
        // A pause is resumable, not a terminal transfer result.
        guard !cancelled else { return nil }
        let needsAttention = hasError || (journal.cloudBackupRequested && !journal.cloudBackupFinished)
        return event(
            completed: journal.entries.count - journal.remainingCount,
            total: journal.entries.count,
            failedCount: journal.remainingCount + (needsAttention ? 1 : 0)
        )
    }
}

@MainActor
final class PlatformProgressNotifier {
    static let shared = PlatformProgressNotifier()
    private let center = UNUserNotificationCenter.current()

    func prepareIfNeeded() async {
        guard PlatformCapabilities.routes.backgroundProgress == .inAppAndNotification else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ event: PlatformProgressNotificationEvent) async {
        guard PlatformCapabilities.routes.backgroundProgress == .inAppAndNotification else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        // Only aggregate counts leave the vault UI, never filenames or errors.
        switch event {
        case .completed(let count):
            content.title = L.string("Import complete")
            content.body = L.format("Saved in Mo Layer: %d", count)
        case .needsAttention(let completed, let total):
            content.title = L.string("Import needs attention")
            content.body = L.format("%d of %d saved in Mo Layer", completed, total)
        }
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
