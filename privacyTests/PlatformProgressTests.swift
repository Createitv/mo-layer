import Testing
@testable import privacy

@MainActor
struct PlatformProgressTests {
    @Test func completedDesktopTransferProducesACompletionNotification() {
        #expect(PlatformProgressNotificationPolicy.event(completed: 4, total: 4, failedCount: 0) == .completed(count: 4))
        #expect(PlatformProgressNotificationPolicy.event(completed: 3, total: 4, failedCount: 1) == .needsAttention(completed: 3, total: 4))
    }

    @Test func pausedTransferDoesNotPostTerminalNotification() {
        let journal = PhotoTransferJournal(assetIDs: ["asset"], folderID: nil, cloudBackupRequested: false)
        #expect(PlatformProgressNotificationPolicy.terminalEvent(journal: journal, cancelled: true, hasError: false) == nil)
    }

    @Test func incompleteCloudBackupNeedsAttentionEvenWhenAllItemsAreLocal() {
        var journal = PhotoTransferJournal(assetIDs: ["asset"], folderID: nil, cloudBackupRequested: true)
        journal.entries[0].state = .verified
        #expect(PlatformProgressNotificationPolicy.terminalEvent(journal: journal, cancelled: false, hasError: false) == .needsAttention(completed: 1, total: 1))
        journal.cloudBackupFinished = true
        #expect(PlatformProgressNotificationPolicy.terminalEvent(journal: journal, cancelled: false, hasError: false) == .completed(count: 1))
    }

    @Test func duplicateAlreadyInVaultCountsAsCompleted() {
        var journal = PhotoTransferJournal(assetIDs: ["asset"], folderID: nil, cloudBackupRequested: false)
        journal.entries[0].state = .duplicate
        #expect(PlatformProgressNotificationPolicy.terminalEvent(journal: journal, cancelled: false, hasError: false) == .completed(count: 1))
        #expect(PlatformProgressNotificationPolicy.terminalEvent(journal: journal, cancelled: false, hasError: true) == .needsAttention(completed: 1, total: 1))
    }

    @Test func unfinishedItemsNeedAttention() {
        var journal = PhotoTransferJournal(assetIDs: ["saved", "failed", "pending"], folderID: nil, cloudBackupRequested: false)
        journal.entries[0].state = .verified
        journal.entries[1].state = .failed
        #expect(PlatformProgressNotificationPolicy.terminalEvent(journal: journal, cancelled: false, hasError: false) == .needsAttention(completed: 1, total: 3))
    }
}
