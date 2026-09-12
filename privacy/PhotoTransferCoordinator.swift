import Combine
import CryptoKit
import Foundation
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import OSLog

enum PhotoTransferSelectionValidation: Equatable {
    case empty
    case missingIdentifiers
    case valid([String])
}

enum PhotoTransferSelectionPolicy {
    nonisolated static func validate(itemCount: Int, identifiers: [String]) -> PhotoTransferSelectionValidation {
        guard itemCount > 0 else { return .empty }
        guard identifiers.count == itemCount else { return .missingIdentifiers }
        return .valid(identifiers)
    }
}

@MainActor
final class PhotoTransferCoordinator: ObservableObject {
    private static let logger = Logger(subsystem: "app.landlady.www.privacy", category: "PhotoTransfer")
    static let shared = PhotoTransferCoordinator()
    @Published private(set) var journal: PhotoTransferJournal?
    @Published private(set) var isRunning = false
    @Published private(set) var isDeleting = false
    @Published private(set) var phase = ""
    @Published var message: String?
    @Published var showReview = false
    private var task: Task<Void, Never>?
    private var stagedTask: Task<StagedPhotoTransfer, Error>?
    private var loaded = false
    private var journalKey: SymmetricKey?
    private let store: PhotoTransferJournalStore

    init(store: PhotoTransferJournalStore = PhotoTransferJournalStore()) {
        self.store = store
    }

    var reviewMessage: String? {
        let stored = message ?? journal?.entries.first(where: { $0.needsImport && $0.error != nil })?.error
        return stored.map { L.persistedString($0) }
    }

    var pinnedVaultIDs: Set<String> {
        Set(journal?.entries.filter { $0.state != .duplicate && $0.state != .kept }.map(\.vaultID) ?? [])
    }
    var progress: Double {
        guard let journal, !journal.entries.isEmpty else { return 0 }
        return Double(journal.entries.filter { !$0.needsImport }.count) / Double(journal.entries.count)
    }

    func restore() {
        guard !loaded else { return }
        do {
            let key = try journalKey ?? VaultCryptoService.ensureRootKey()
            journal = try store.load(key: key)
            journalKey = key
            loaded = true
            PhotoTransferSource.clearAbandonedStaging()
        } catch {
            message = L.string("The saved transfer could not be opened. No system originals will be deleted.")
        }
    }

    func start(assetIdentifiers: [String?], folderID: String?, context: ModelContext, sync: CloudKitSyncService, subscription: SubscriptionManager) {
        if !loaded { restore() }
        guard loaded else { return }
        guard !isRunning, !isDeleting, journal == nil else { showReview = true; return }
        let validation = PhotoTransferSelectionPolicy.validate(
            itemCount: assetIdentifiers.count,
            identifiers: assetIdentifiers.compactMap { $0 }
        )
        guard case .valid(let ids) = validation else {
            if validation == .missingIdentifiers {
                message = L.string("The selected items could not be linked to your photo library. Keep Full Access enabled, reopen Photos, and try again. Originals have not been deleted.")
            }
            return
        }
        do {
            try persist(PhotoTransferJournal(assetIDs: ids, folderID: folderID, cloudBackupRequested: subscription.canImportAndSync))
            loaded = true
            showReview = true
            resume(context: context, sync: sync, subscription: subscription)
        } catch { message = L.string(error.localizedDescription) }
    }

    func resume(context: ModelContext, sync: CloudKitSyncService, subscription: SubscriptionManager) {
        guard let journal, !isRunning, !isDeleting else { return }
        let context = ModelContext(context.container)
        context.autosaveEnabled = false
        isRunning = true
        message = nil
        PhotoTransferBackground.shared.begin(total: journal.entries.count * (journal.cloudBackupRequested ? 2 : 1)) { [weak self] in self?.pause() }
        task = Task { @MainActor in
            defer {
                isRunning = false
                task = nil
                phase = ""
                stagedTask = nil
                PhotoTransferBackground.shared.finish(success: self.journal?.remainingCount == 0 && (self.journal?.cloudBackupRequested != true || self.journal?.cloudBackupFinished == true) && !Task.isCancelled)
            }
            await PlatformProgressNotifier.shared.prepareIfNeeded()
            do {
                try Task.checkCancellation()
                guard !context.container.configurations.contains(where: { $0.isStoredInMemoryOnly }) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let key = try journalKey ?? VaultCryptoService.ensureRootKey()
                let indices = journal.entries.indices.filter { journal.entries[$0].needsImport }
                // Only one prefetched asset on disk, alongside the current item.
                var prefetch: Task<StagedPhotoTransfer, Error>?
                if let first = indices.first {
                    let id = journal.entries[first].id
                    prefetch = Task { try await PhotoTransferSource.stage(identifier: id) }
                }
                stagedTask = prefetch
                for (position, index) in indices.enumerated() {
                    guard !Task.isCancelled else {
                        prefetch?.cancel()
                        if let staged = try? await prefetch?.value { staged.remove() }
                        break
                    }
                    phase = L.format("Saving photo %d of %d", index + 1, journal.entries.count)
                    let current = prefetch
                    let result: Result<StagedPhotoTransfer, Error>
                    do { result = .success(try await current!.value) } catch { result = .failure(error) }
                    prefetch = nil
                    if position + 1 < indices.count, !Task.isCancelled {
                        let nextID = journal.entries[indices[position + 1]].id
                        prefetch = Task { try await PhotoTransferSource.stage(identifier: nextID) }
                    }
                    stagedTask = prefetch
                    do {
                        let staged = try result.get()
                        defer { staged.remove() }
                        try Task.checkCancellation()
                        let data = try await staged.payload()
                        let receipt = try await PhotoTransferStorage.commit(data: data, staged: staged, entry: journal.entries[index],
                            folderID: journal.folderID, context: context, rootKey: key)
                        try update(index: index) { $0 = receipt }
                    } catch is CancellationError {
                        prefetch?.cancel()
                        if let staged = try? await prefetch?.value { staged.remove() }
                        break
                    } catch {
                        let nsError = error as NSError
                        Self.logger.error("Import failed at item \(index + 1): domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
                        do {
                            try update(index: index) { $0.state = .failed; $0.error = L.string(error.localizedDescription) }
                            if error is TransferError || error is VaultStorageQuota.LimitError { throw error }
                        } catch {
                            prefetch?.cancel()
                            if let staged = try? await prefetch?.value { staged.remove() }
                            throw error // Never continue after a checkpoint write failure.
                        }
                    }
                    PhotoTransferBackground.shared.update(completed: position + 1, total: max(1, indices.count + (journal.cloudBackupRequested ? journal.entries.count : 0)))
                }
                try Task.checkCancellation()
                if journal.cloudBackupRequested, subscription.canImportAndSync {
                    phase = L.string("Uploading encrypted copies to iCloud")
                    // Only durable items are uploaded; syncStatus is persisted per item for restart.
                    for (index, entry) in (self.journal?.entries ?? []).enumerated() where !entry.needsImport && entry.state != .duplicate {
                        try Task.checkCancellation()
                        guard subscription.canImportAndSync else { break }
                        if let item = try PhotoTransferStorage.item(id: entry.vaultID, context: context), item.deletedAt == nil, item.syncStatus != .synced {
                            let uploaded = await sync.syncItem(item)
                            try context.save()
                            if !uploaded {
                                message = item.lastSyncError ?? L.string("Local copies are saved separately from iCloud. Cloud backup is pending or incomplete.")
                                break
                            }
                        }
                        PhotoTransferBackground.shared.update(completed: journal.entries.count + index + 1, total: journal.entries.count * 2)
                    }
                    var updated = self.journal!
                    updated.cloudBackupFinished = try updated.remainingCount == 0 && (updated.entries.filter { $0.state != .duplicate }.allSatisfy {
                        try PhotoTransferStorage.item(id: $0.vaultID, context: context)?.syncStatus == .synced
                    })
                    try persist(updated)
                }
            } catch is CancellationError {
                message = L.string("Transfer paused. Unlock Mo Layer and tap Continue to resume. System originals are kept.")
            } catch { message = L.string(error.localizedDescription) }
            if PlatformCapabilities.routes.backgroundProgress == .inAppAndNotification,
               let latest = self.journal,
               let event = PlatformProgressNotificationPolicy.terminalEvent(
                   journal: latest,
                   cancelled: Task.isCancelled,
                   hasError: message != nil
               ) {
                await PlatformProgressNotifier.shared.post(event)
            }
        }
    }

    func pause() {
        task?.cancel()
        stagedTask?.cancel()
        // Keep the running flag until the current write/checkpoint finishes.
        message = L.string("Transfer paused. Unlock Mo Layer and tap Continue to resume. System originals are kept.")
    }

    func deleteVerifiedOriginals(context: ModelContext) async {
        guard let journal, !isRunning, !isDeleting, UIApplication.shared.applicationState == .active else { return }
        let context = ModelContext(context.container)
        context.autosaveEnabled = false
        isDeleting = true
        defer { isDeleting = false; phase = "" }
        message = nil
        do {
            let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard authorization == .authorized || authorization == .limited else { throw PhotoTransferSource.SourceError.inaccessible }
            let key = try journalKey ?? VaultCryptoService.ensureRootKey()
            var eligible: [(Int, PHAsset)] = []
            for (index, entry) in journal.entries.enumerated() where entry.canReviewDeletion {
                phase = L.format("Verifying original %d of %d", index + 1, journal.entries.count)
                do {
                    guard let item = try PhotoTransferStorage.item(id: entry.vaultID, context: context) else { throw CocoaError(.fileNoSuchFile) }
                    let staged = try await PhotoTransferSource.stage(identifier: entry.id)
                    defer { staged.remove() }
                    let data = try await staged.payload()
                    let kind = staged.kind
                    let sourceDigest = try await Task.detached { try PhotoTransferStorage.contentFingerprint(data: data, kind: kind) }.value
                    let localDigest = try await PhotoTransferStorage.verifiedFingerprint(item: item, rootKey: key)
                    guard staged.modifiedAt == entry.sourceModifiedAt,
                          staged.preservesAllResources,
                          PhotoTransferSafety.canDelete(entry: entry, storedFingerprint: localDigest, sourceFingerprint: sourceDigest,
                            localExists: VaultFileStore.fileExists(path: item.encryptedFilePath), itemDeleted: item.deletedAt != nil),
                          let asset = PHAsset.fetchAssets(withLocalIdentifiers: [entry.id], options: nil).firstObject else { throw PhotoTransferSource.SourceError.sourceChanged }
                    eligible.append((index, asset))
                } catch {
                    try update(index: index) { $0.error = L.string(error.localizedDescription) }
                }
            }
            guard !eligible.isEmpty else {
                message = L.string("No originals could be safely deleted. Review the transfer details and retry.")
                return
            }
            guard UIApplication.shared.applicationState == .active else { return }
            // Persist intent BEFORE opening the system confirmation. A crash never becomes a success.
            var intent = self.journal!
            for (index, _) in eligible { intent.entries[index].state = .deletionRequested }
            try persist(intent)
            var assets: [PHAsset] = []
            for (index, _) in eligible {
                let entry = intent.entries[index]
                guard let fresh = PHAsset.fetchAssets(withLocalIdentifiers: [entry.id], options: nil).firstObject,
                      fresh.modificationDate == entry.sourceModifiedAt,
                      let item = try PhotoTransferStorage.item(id: entry.vaultID, context: context),
                      item.deletedAt == nil, VaultFileStore.fileExists(path: item.encryptedFilePath) else { continue }
                assets.append(fresh)
            }
            guard !assets.isEmpty else { return }
            let submittedIDs = Set(assets.map(\.localIdentifier))
            do {
                try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets as NSArray) }
            } catch {
                message = L.string("System deletion was cancelled or failed. Your Mo Layer copies are safe; originals were not confirmed deleted.")
                return
            }
            let remaining = PHAsset.fetchAssets(withLocalIdentifiers: assets.map(\.localIdentifier), options: nil)
            var stillPresent = Set<String>()
            remaining.enumerateObjects { asset, _, _ in stillPresent.insert(asset.localIdentifier) }
            var updated = self.journal!
            for (index, asset) in eligible where submittedIDs.contains(asset.localIdentifier) {
                // Absence alone is never proof: require successful transaction AND continuing full visibility.
                if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized && !stillPresent.contains(asset.localIdentifier) {
                    updated.entries[index].state = .removed
                    updated.entries[index].error = nil
                } else {
                    updated.entries[index].error = L.string("Deletion needs confirmation. Check Photos; Mo Layer cannot verify it with the current photo access.")
                }
            }
            try persist(updated)
        } catch { message = L.string(error.localizedDescription) }
    }

    func keepOriginalsAndFinish() {
        guard !isRunning, !isDeleting else { return }
        do {
            // Only the transfer journal is discarded; never vault content or system photos.
            try store.remove()
            journal = nil
            showReview = false
            message = nil
        } catch { message = L.string(error.localizedDescription) }
    }

    private func update(index: Int, change: (inout PhotoTransferEntry) -> Void) throws {
        guard var updated = journal else { return }
        change(&updated.entries[index])
        try persist(updated)
    }
    private func persist(_ updated: PhotoTransferJournal) throws {
        let key = try journalKey ?? VaultCryptoService.ensureRootKey()
        try store.save(updated, key: key)
        journalKey = key
        journal = updated
    }
    enum TransferError: LocalizedError {
        case limit
        var errorDescription: String? { "The vault import limit has been reached. Open Pro or free space in the vault, then continue." }
    }
}
