import CryptoKit
import Foundation
import Photos
import SwiftData
import Testing
import UIKit
@testable import privacy

@MainActor
@Suite(.serialized)
struct PhotoTransferTests {
    @Test func livePhotoPreviewThenFinalCallbackResumesOnlyOnce() async {
        let completion = LivePhotoRequestCompletion()
        let result = await withCheckedContinuation { continuation in
            completion.install(continuation)
            #expect(!completion.receive(nil, info: [PHLivePhotoInfoIsDegradedKey: true]))
            #expect(completion.receive(nil, info: [PHLivePhotoInfoIsDegradedKey: false]))
            #expect(!completion.receive(nil, info: [:]))
            completion.cancel()
        }
        #expect(result == nil)
    }

    @Test func livePhotoCancellationBeforeRequestAndLateResultDoNotDoubleResume() async {
        let completion = LivePhotoRequestCompletion()
        completion.cancel()
        let result = await withCheckedContinuation { continuation in
            completion.install(continuation)
            #expect(!completion.receive(nil, info: [:]))
            completion.cancel()
        }
        #expect(result == nil)
    }

    @Test func livePhotoErrorEndsRequestEvenIfMarkedDegraded() async {
        let completion = LivePhotoRequestCompletion()
        let result = await withCheckedContinuation { continuation in
            completion.install(continuation)
            #expect(completion.receive(nil, info: [PHLivePhotoInfoIsDegradedKey: true, PHLivePhotoInfoErrorKey: CocoaError(.fileReadCorruptFile)]))
            #expect(!completion.receive(nil, info: [:]))
        }
        #expect(result == nil)
    }

    @Test func editedAndAlternateResourcesImportInsteadOfBeingRejected() throws {
        let edited = try PhotoTransferSource.selection(resources: [.photo, .adjustmentData, .fullSizePhoto], live: false)
        #expect(edited.indices == [2])
        #expect(edited.kind == .image)
        #expect(!edited.preservesAllResources)
        let rawPair = try PhotoTransferSource.selection(resources: [.photo, .alternatePhoto], live: false)
        #expect(rawPair.indices == [0])
        #expect(!rawPair.preservesAllResources)
        let video = try PhotoTransferSource.selection(resources: [.video, .adjustmentData, .fullSizeVideo], live: false, video: true)
        #expect(video.indices == [2])
        #expect(video.kind == .video)
        #expect(!video.preservesAllResources)
    }

    @Test func editedLivePhotoUsesMatchingCurrentPairAndNeverMixesVersions() throws {
        let edited = try PhotoTransferSource.selection(resources: [.pairedVideo, .fullSizePairedVideo, .photo, .adjustmentData, .fullSizePhoto], live: true)
        #expect(edited.indices == [4, 1])
        #expect(edited.kind == .livePhoto)
        #expect(!edited.preservesAllResources)
        let stillOnly = try PhotoTransferSource.selection(resources: [.photo, .pairedVideo, .fullSizePhoto, .adjustmentData], live: true)
        #expect(stillOnly.indices == [2])
        #expect(stillOnly.kind == .image)
        #expect(!stillOnly.preservesAllResources)
        let original = try PhotoTransferSource.selection(resources: [.pairedVideo, .photo], live: true)
        #expect(original.indices == [1, 0])
        #expect(original.preservesAllResources)
        #expect(throws: (any Error).self) { try PhotoTransferSource.selection(resources: [.adjustmentData], live: false) }
    }

    @Test func compatibleImportIsSavedButNeverAllowsDeletingExtraOriginalResources() async throws {
        let container = try ModelContainer(for: VaultItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let key = try VaultCryptoService.ensureRootKey()
        let entry = PhotoTransferEntry(id: "edited-fixture")
        let data = Data("edited-\(UUID())".utf8)
        let staged = StagedPhotoTransfer(directory: URL(fileURLWithPath: "/unused"), files: [], names: ["fixture.bin"], kind: .other, mimeType: "application/octet-stream", preservesAllResources: false)
        defer {
            if let item = try? PhotoTransferStorage.item(id: entry.vaultID, context: context) {
                VaultFileStore.remove(path: item.encryptedFilePath)
                VaultFileStore.remove(path: item.encryptedThumbPath)
            }
        }
        let receipt = try await PhotoTransferStorage.commit(data: data, staged: staged, entry: entry, folderID: nil, context: context, rootKey: key)
        #expect(receipt.state == .savedKeepingOriginal)
        var journal = PhotoTransferJournal(assetIDs: [entry.id], folderID: nil, cloudBackupRequested: false)
        journal.entries = [receipt]
        let restored = try JSONDecoder().decode(PhotoTransferJournal.self, from: JSONEncoder().encode(journal))
        #expect(restored.savedCount == 1)
        #expect(restored.remainingCount == 0)
        #expect(restored.deletionCount == 0)
        #expect(!PhotoTransferSafety.canDelete(entry: receipt, storedFingerprint: receipt.fingerprint, sourceFingerprint: receipt.fingerprint, localExists: true, itemDeleted: false))
        let replay = try await PhotoTransferStorage.commit(data: data, staged: staged, entry: entry, folderID: nil, context: context, rootKey: key)
        #expect(replay == receipt)
        #expect(try context.fetchCount(FetchDescriptor<VaultItem>()) == 1)
    }

    @Test func savedTransferMessagesResolveBackToTheirKeyInEveryLanguage() throws {
        let key = "This edited or multi-resource photo cannot yet be transferred losslessly. The original has been kept."
        for code in AppLanguage.allCases.compactMap(\.bundleCode) {
            let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            let savedMessage = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
            #expect(savedMessage != "MISSING")
            #expect(L.canonicalKey(forPersistedString: savedMessage) == key)
        }
        #expect(L.canonicalKey(forPersistedString: "Unknown system error") == "Unknown system error")
    }

    @Test func transferCompletionFormatsCountsInEveryLanguage() throws {
        let keys = ["Saved in Mo Layer: %d", "Delete originals (%d)", "Items: %d", "Items remaining: %d"]
        for language in AppLanguage.allCases where language.bundleCode != nil {
            let path = try #require(Bundle.main.path(forResource: language.bundleCode!, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            for key in keys {
                let format = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
                #expect(format != "MISSING")
                for count in [0, 1, 425] {
                    let rendered = String(format: format, locale: language.locale, count)
                    #expect(!rendered.contains("%d"))
                    #expect(rendered.contains(String(count)))
                }
            }
        }
    }

    @Test func restoredFailureShowsReasonWithoutOpeningReviewAndCanBeFinished() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotoTransferJournalStore(url: directory.appendingPathComponent("transfer.enc"))
        var journal = PhotoTransferJournal(assetIDs: ["saved", "failed"], folderID: nil, cloudBackupRequested: false)
        journal.entries[0].state = .verified
        journal.entries[1].state = .failed
        journal.entries[1].error = "Resource download failed"
        let key = try VaultCryptoService.ensureRootKey()
        try store.save(journal, key: key)
        let coordinator = PhotoTransferCoordinator(store: store)
        coordinator.restore()
        #expect(!coordinator.showReview)
        #expect(coordinator.reviewMessage == "Resource download failed")
        #expect(coordinator.journal?.savedCount == 1)
        coordinator.keepOriginalsAndFinish()
        #expect(coordinator.journal == nil)
        #expect(try store.load(key: key) == nil)
        #expect(!coordinator.showReview)
    }

    @Test func retryFailureDoesNotDismissOrReopenReview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PhotoTransferJournalStore(url: directory.appendingPathComponent("transfer.enc"))
        try store.save(PhotoTransferJournal(assetIDs: ["pending"], folderID: nil, cloudBackupRequested: false), key: VaultCryptoService.ensureRootKey())
        let coordinator = PhotoTransferCoordinator(store: store)
        coordinator.restore()
        // An in-memory destination fails before any PhotoKit or network access.
        let container = try ModelContainer(for: VaultItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        coordinator.showReview = true
        coordinator.resume(context: ModelContext(container), sync: CloudKitSyncService(), subscription: SubscriptionManager())
        #expect(coordinator.showReview)
        #expect(coordinator.isRunning)
        coordinator.showReview = false // User closes while the task runs.
        for _ in 0..<100 where coordinator.isRunning { await Task.yield() }
        #expect(!coordinator.isRunning)
        #expect(!coordinator.showReview)
        #expect(coordinator.reviewMessage != nil)
        #expect(coordinator.journal?.remainingCount == 1)
    }

    @Test func completionReviewOnlyDeletesAfterExplicitDeleteAction() {
        #expect(PhotoTransferReviewPolicy.operation(for: .deleteOriginals, transferComplete: true) == .deleteVerifiedOriginals)
        #expect(PhotoTransferReviewPolicy.operation(for: .keepOriginals, transferComplete: true) == .finishKeepingOriginals)
        #expect(PhotoTransferReviewPolicy.operation(for: .close, transferComplete: true) == .finishKeepingOriginals)
    }

    @Test func closingAnUnfinishedTransferKeepsItResumable() {
        #expect(PhotoTransferReviewPolicy.operation(for: .close, transferComplete: false) == .dismissOnly)
    }

    @Test func livePhotoFingerprintSurvivesDifferentPropertyListEncodings() throws {
        let package = LivePhotoPackage(stillData: Data("photo".utf8), pairedVideoData: Data("video".utf8), stillFilename: "photo.heic", pairedVideoFilename: "video.mov")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let binary = try encoder.encode(package)
        encoder.outputFormat = .xml
        let xml = try encoder.encode(package)
        #expect(binary != xml)
        #expect(try PhotoTransferStorage.contentFingerprint(data: binary, kind: .livePhoto) == PhotoTransferStorage.contentFingerprint(data: xml, kind: .livePhoto))
        var missingVideo = package
        missingVideo.pairedVideoData = Data()
        let broken = try encoder.encode(missingVideo)
        #expect(throws: (any Error).self) { try PhotoTransferStorage.contentFingerprint(data: broken, kind: .livePhoto) }
    }

    @Test func unreadableImagesAreRejectedBeforeADeletionReceipt() throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        try PhotoTransferSource.validateImageData(data)
        #expect(throws: (any Error).self) { try PhotoTransferSource.validateImageData(Data("not an image".utf8)) }
    }

    @Test func failedPendingDuplicateAndKeptNeverAuthorizeDeletion() {
        for state in [PhotoTransferEntry.State.pending, .failed, .duplicate, .kept, .removed] {
            var entry = PhotoTransferEntry(id: "source")
            entry.state = state
            entry.fingerprint = "digest"
            #expect(!PhotoTransferSafety.canDelete(entry: entry, storedFingerprint: "digest", sourceFingerprint: "digest", localExists: true, itemDeleted: false))
        }
    }

    @Test func deletionRequiresBothMatchingCopiesAndLiveVaultItem() {
        var entry = PhotoTransferEntry(id: "source")
        entry.state = .verified
        entry.fingerprint = "digest"
        #expect(PhotoTransferSafety.canDelete(entry: entry, storedFingerprint: "digest", sourceFingerprint: "digest", localExists: true, itemDeleted: false))
        #expect(!PhotoTransferSafety.canDelete(entry: entry, storedFingerprint: "other", sourceFingerprint: "digest", localExists: true, itemDeleted: false))
        #expect(!PhotoTransferSafety.canDelete(entry: entry, storedFingerprint: "digest", sourceFingerprint: "edited", localExists: true, itemDeleted: false))
        #expect(!PhotoTransferSafety.canDelete(entry: entry, storedFingerprint: "digest", sourceFingerprint: "digest", localExists: false, itemDeleted: false))
        #expect(!PhotoTransferSafety.canDelete(entry: entry, storedFingerprint: "digest", sourceFingerprint: "digest", localExists: true, itemDeleted: true))
        entry.fingerprint = nil
        #expect(!PhotoTransferSafety.canDelete(entry: entry, storedFingerprint: nil, sourceFingerprint: nil, localExists: true, itemDeleted: false))
    }

    @Test func livePhotoRequiresBothResourcesAndRejectsLossyFallbacks() {
        #expect(PhotoTransferSource.supports(resources: [.photo, .pairedVideo], live: true))
        #expect(!PhotoTransferSource.supports(resources: [.photo], live: true))
        #expect(!PhotoTransferSource.supports(resources: [.photo, .pairedVideo, .adjustmentData], live: true))
        #expect(!PhotoTransferSource.supports(resources: [.photo, .alternatePhoto], live: false))
        #expect(PhotoTransferSource.supports(resources: [.video], live: false))
        #expect(!PhotoTransferSource.supports(resources: [], live: false))
    }

    @Test func fourHundredItemJournalResumesOnlyUnfinishedEntries() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("journal.enc")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PhotoTransferJournalStore(url: url)
        let key = SymmetricKey(size: .bits256)
        var journal = PhotoTransferJournal(assetIDs: (0..<425).map { "asset-\($0)" }, folderID: "private", cloudBackupRequested: true)
        for index in 0..<201 { journal.entries[index].state = .verified; journal.entries[index].fingerprint = "digest-\(index)" }
        journal.entries[201].state = .failed
        try store.save(journal, key: key)
        let loaded = try store.load(key: key)
        let restored = try #require(loaded)
        #expect(restored == journal)
        #expect(restored.remainingCount == 224)
        #expect(restored.savedCount == 201)
        #expect(restored.entries[202].vaultID == journal.entries[202].vaultID)
        #expect(!(try Data(contentsOf: url)).contains(Data("asset-".utf8)))
    }

    @Test func journalDeduplicatesSourceIdentifiersInSelectionOrder() {
        let journal = PhotoTransferJournal(assetIDs: ["b", "a", "b"], folderID: nil, cloudBackupRequested: false)
        #expect(journal.entries.map(\.id) == ["b", "a"])
    }

    @Test func interruptedDeletionRemainsUnconfirmedAfterRestart() throws {
        var journal = PhotoTransferJournal(assetIDs: ["source"], folderID: nil, cloudBackupRequested: false)
        journal.entries[0].state = .deletionRequested
        let restored = try JSONDecoder().decode(PhotoTransferJournal.self, from: JSONEncoder().encode(journal))
        #expect(restored.removedCount == 0)
        #expect(restored.deletionCount == 1)
    }

    @Test func corruptedJournalNeverBecomesAnEmptySuccessfulTask() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("corrupted".utf8).write(to: url)
        #expect(throws: (any Error).self) { try PhotoTransferJournalStore(url: url).load(key: SymmetricKey(size: .bits256)) }
    }

    @Test func encryptedCopyReadbackDetectsTamperingAndWrongKey() throws {
        let key = SymmetricKey(size: .bits256)
        let payload = Data(repeating: 42, count: 1_048_576)
        var encrypted = try VaultCryptoService.encrypt(payload, using: key)
        #expect(try PhotoTransferStorage.fingerprint(encrypted: encrypted, fileKey: key) == VaultImportFingerprint.digest(for: payload))
        #expect(throws: (any Error).self) { try PhotoTransferStorage.fingerprint(encrypted: encrypted, fileKey: SymmetricKey(size: .bits256)) }
        encrypted[encrypted.count / 2] ^= 1
        #expect(throws: (any Error).self) { try PhotoTransferStorage.fingerprint(encrypted: encrypted, fileKey: key) }
    }

    @Test func commitCanReplayAfterCrashBetweenDatabaseAndJournalSave() async throws {
        let container = try ModelContainer(for: VaultItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let key = try VaultCryptoService.ensureRootKey()
        let entry = PhotoTransferEntry(id: "fixture-source")
        let data = Data("unique-\(UUID())".utf8)
        let staged = StagedPhotoTransfer(directory: URL(fileURLWithPath: "/unused"), files: [], names: ["fixture.bin"], kind: .other, mimeType: "application/octet-stream", modifiedAt: Date(), location: nil)
        defer {
            if let item = try? PhotoTransferStorage.item(id: entry.vaultID, context: context) {
                VaultFileStore.remove(path: item.encryptedFilePath)
                VaultFileStore.remove(path: item.encryptedThumbPath)
            }
        }
        let receipt = try await PhotoTransferStorage.commit(data: data, staged: staged, entry: entry, folderID: nil, context: context, rootKey: key)
        #expect(receipt.state == .verified)
        // Simulate durable DB commit but loss of receipt: retry the ORIGINAL pending entry.
        let replay = try await PhotoTransferStorage.commit(data: data, staged: staged, entry: entry, folderID: nil, context: context, rootKey: key)
        #expect(replay == receipt)
        #expect(try context.fetchCount(FetchDescriptor<VaultItem>()) == 1)
        let duplicate = try await PhotoTransferStorage.commit(data: data, staged: staged, entry: PhotoTransferEntry(id: "other-source"), folderID: nil, context: context, rootKey: key)
        #expect(duplicate.state == .duplicate)
        #expect(!duplicate.canReviewDeletion)
    }

    @Test func replayRejectsChangedSourceInsteadOfReplacingVerifiedCopy() async throws {
        let container = try ModelContainer(for: VaultItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let key = try VaultCryptoService.ensureRootKey()
        let entry = PhotoTransferEntry(id: "fixture")
        let staged = StagedPhotoTransfer(directory: URL(fileURLWithPath: "/unused"), files: [], names: ["fixture.bin"], kind: .other, mimeType: "application/octet-stream", modifiedAt: nil, location: nil)
        _ = try await PhotoTransferStorage.commit(data: Data("before".utf8), staged: staged, entry: entry, folderID: nil, context: context, rootKey: key)
        defer {
            if let item = try? PhotoTransferStorage.item(id: entry.vaultID, context: context) { VaultFileStore.remove(path: item.encryptedFilePath) }
        }
        await #expect(throws: (any Error).self) {
            try await PhotoTransferStorage.commit(data: Data("after".utf8), staged: staged, entry: entry, folderID: nil, context: context, rootKey: key)
        }
    }
}
