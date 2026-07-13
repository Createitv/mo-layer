import Combine
import AVFoundation
import CloudKit
import CryptoKit
import Foundation
import OSLog
import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

enum RemoteVaultRestoreCheck: Equatable {
    case noRemoteVault
    case needsRecoveryKey
    case restoredAutomatically(CloudAssetDownloadSummary)
    case failed(String)
}

struct CloudAssetDownloadSummary: Equatable {
    var indexedItems = 0
    var total = 0
    var succeeded = 0
    var failed = 0
    var failureMessages: [String] = []

    var displayText: String {
        if total == 0 {
            if indexedItems > 0 {
                return L.format("%d encrypted item(s) restored from iCloud. Originals download when opened.", indexedItems)
            }
            return L.string("iCloud backup restored. No encrypted files needed downloading.")
        }
        if failed == 0 {
            return L.format("%d encrypted file(s) downloaded from iCloud.", succeeded)
        }
        return L.format("%d encrypted file(s) downloaded, %d failed.", succeeded, failed)
    }
}

enum VaultCloudToLocalSyncPolicy {
    static let automaticDownloadsOriginals = true
    static let manualRefreshDownloadsOriginals = true
    static let syncedHomeCategories: [VaultCategory] = [.album, .audio, .documents]
}

enum VaultCloudAssetDownloadPolicy {
    static func shouldDownload(_ item: VaultItem) -> Bool {
        item.deletedAt == nil
            && item.kind != .link
            && (item.assetState != .local || !VaultFileStore.fileExists(path: item.encryptedFilePath))
    }
}

struct VaultImportPreparedItem {
    let itemId: String
    let encryptedFilePath: String
    let encryptedThumbPath: String?
    let encryptedMetadata: Data
    let encryptedFileKey: Data
    let importFingerprint: String?
}

enum VaultImportResult: Equatable {
    case imported
    case skippedDuplicate
    case failed
}

enum VaultImportBatchPolicy {
    static let saveInterval = 10

    static func shouldSave(afterImportedCount importedCount: Int) -> Bool {
        importedCount > 0 && importedCount % saveInterval == 0
    }
}

enum VaultImportArtifactBuilder {
    static func fingerprint(for data: Data, kind: VaultItemKind) async -> String? {
        switch kind {
        case .link:
            return nil
        case .image, .livePhoto, .video, .audio, .document, .archive, .other:
            return VaultImportFingerprint.digest(for: data)
        }
    }

    static func prepare(
        data: Data,
        originalName: String,
        mimeType: String,
        source: String,
        kind: VaultItemKind,
        importFingerprint: String?
    ) async throws -> VaultImportPreparedItem {
        let rootKey = try VaultCryptoService.ensureRootKey()
        let fileKey = VaultCryptoService.newFileKey()
        let itemId = UUID().uuidString
        let encryptedFile = try VaultCryptoService.encrypt(data, using: fileKey)
        let encryptedFilePath = try VaultFileStore.writeEncryptedObject(encryptedFile, itemId: itemId)

        let thumbData = await makeThumbnailData(
            from: data,
            kind: kind,
            originalName: originalName,
            mimeType: mimeType
        )
        let encryptedThumbPath: String?
        if let thumbData {
            let encryptedThumb = try VaultCryptoService.encrypt(thumbData, using: fileKey)
            encryptedThumbPath = try VaultFileStore.writeEncryptedThumb(encryptedThumb, itemId: itemId)
        } else {
            encryptedThumbPath = nil
        }

        let metadata = VaultMetadata(
            originalName: originalName,
            mimeType: mimeType,
            source: source,
            note: "",
            importedAt: Date(),
            remoteURL: nil,
            originalExtension: (originalName as NSString).pathExtension
        )
        let encryptedMetadata = try VaultCryptoService.encryptCodable(metadata, using: rootKey)
        let encryptedFileKey = try VaultCryptoService.wrapFileKey(fileKey, rootKey: rootKey)

        return VaultImportPreparedItem(
            itemId: itemId,
            encryptedFilePath: encryptedFilePath,
            encryptedThumbPath: encryptedThumbPath,
            encryptedMetadata: encryptedMetadata,
            encryptedFileKey: encryptedFileKey,
            importFingerprint: importFingerprint
        )
    }

    private static func makeThumbnailData(
        from data: Data,
        kind: VaultItemKind,
        originalName: String,
        mimeType: String
    ) async -> Data? {
        switch kind {
        case .image:
            guard let image = UIImage(data: data) else { return nil }
            return renderThumbnailData(from: image)
        case .livePhoto:
            guard let package = try? PropertyListDecoder().decode(LivePhotoPackage.self, from: data),
                  let image = UIImage(data: package.stillData) else {
                return nil
            }
            return renderThumbnailData(from: image)
        case .video:
            return await makeVideoThumbnailData(
                from: data,
                preferredExtension: videoFileExtension(originalName: originalName, mimeType: mimeType)
            )
        default:
            return nil
        }
    }

    private static func makeVideoThumbnailData(from data: Data, preferredExtension: String?) async -> Data? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(preferredExtension ?? "mov")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            let asset = AVURLAsset(url: temporaryURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity

            for time in videoThumbnailTimes {
                if let image = try? await generateImage(with: generator, at: time),
                   let data = renderThumbnailData(from: UIImage(cgImage: image)) {
                    return data
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    private static var videoThumbnailTimes: [CMTime] {
        [
            CMTime(seconds: 0, preferredTimescale: 600),
            CMTime(seconds: 0.1, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600),
            CMTime(seconds: 1, preferredTimescale: 600)
        ]
    }

    private static func videoFileExtension(originalName: String, mimeType: String) -> String? {
        let nameExtension = (originalName as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameExtension.isEmpty {
            return nameExtension.lowercased()
        }

        let mimeExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension
        return mimeExtension?.isEmpty == false ? mimeExtension : nil
    }

    private static func generateImage(with generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile))
                }
            }
        }
    }

    private static func renderThumbnailData(from image: UIImage) -> Data? {
        let targetSize = CGSize(width: 360, height: 360)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.jpegData(withCompressionQuality: 0.72) { _ in
            let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (targetSize.width - size.width) / 2, y: (targetSize.height - size.height) / 2)
            image.draw(in: CGRect(origin: origin, size: size))
        }
    }
}

@MainActor
final class VaultStore: ObservableObject {
    static let innerVaultFolderId = "system.innerVault"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "VaultStore")
    private var thumbnailCache: [String: UIImage] = [:]
    @Published var lastError: String?
    @Published var restoreStatusMessage: String?
    @Published private(set) var allowsVaultWrites = false

    func setWriteAccess(_ isAllowed: Bool) {
        allowsVaultWrites = isAllowed
    }

    func hasLocalVaultData(context: ModelContext) -> Bool {
        do {
            var manifestDescriptor = FetchDescriptor<VaultManifest>()
            manifestDescriptor.fetchLimit = 1
            if try !context.fetch(manifestDescriptor).isEmpty {
                return true
            }

            var itemDescriptor = FetchDescriptor<VaultItem>()
            itemDescriptor.fetchLimit = 1
            if try !context.fetch(itemDescriptor).isEmpty {
                return true
            }
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func requireWriteAccess() -> Bool {
        guard allowsVaultWrites else {
            lastError = L.string("Renew Pro to add, edit, delete, or sync vault content.")
            return false
        }
        return true
    }

    func bootstrap(
        context: ModelContext,
        sync: CloudKitSyncService,
        allowsCloudSync: Bool = true,
        allowsCloudWrite: Bool? = nil
    ) async {
        let canWriteCloud = allowsCloudWrite ?? allowsCloudSync
        do {
            try VaultFileStore.prepareDirectories()
            try repairStoredFileReferences(context: context)
            try await repairMissingVideoThumbnails(context: context)

            var descriptor = FetchDescriptor<VaultManifest>()
            descriptor.fetchLimit = 1
            if try context.fetch(descriptor).isEmpty {
                if allowsCloudSync, let remoteManifest = await sync.fetchRemoteManifest() {
                    if try restoreRemoteManifestUsingAvailableKey(remoteManifest, context: context) {
                        await pullCloudDecoyNotes(context: context, sync: sync)
                        let summary = await downloadAllCloudAssets(context: context, sync: sync)
                        restoreStatusMessage = summary.displayText
                    } else {
                        lastError = L.string("An existing iCloud vault was found. Restore it with iCloud Keychain or your recovery key before creating a new vault.")
                    }
                    return
                } else {
                    let rootKey = try VaultCryptoService.ensureRootKey()
                    let manifest = try makeLocalManifest(rootKey: rootKey)
                    context.insert(manifest)
                    try context.save()
                    if canWriteCloud {
                        _ = await sync.syncManifest(manifest)
                    }
                    try? context.save()
                }
            }

            await syncPendingChanges(context: context, sync: sync, allowsCloudSync: canWriteCloud)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restoreRootKeyFromCloud(recoveryKey: String, context: ModelContext, sync: CloudKitSyncService) async -> Bool {
        do {
            guard let remoteManifest = await sync.fetchRemoteManifest(),
                  let package = remoteManifest["encryptedRootKeyPackage"] as? Data,
                  !package.isEmpty else {
                lastError = L.string("No iCloud recovery package was found.")
                return false
            }

            let rootKey = try VaultCryptoService.restoreRootKey(from: package, recoveryKey: recoveryKey)
            let existingManifests = try context.fetch(FetchDescriptor<VaultManifest>())
            for manifest in existingManifests {
                context.delete(manifest)
            }
            let manifest = makeManifest(from: remoteManifest)
            manifest.encryptedRootKeyPackage = try VaultCryptoService.makeRootKeyPackage(recoveryKey: recoveryKey)
            manifest.encryptedVaultName = try VaultCryptoService.encryptString("Private Vault", using: rootKey)
            manifest.syncStatus = .synced
            context.insert(manifest)
            try context.save()
            try? VaultCryptoService.syncRootKeyToICloudKeychain()
            await pullCloudDecoyNotes(context: context, sync: sync)
            let summary = await downloadAllCloudAssets(context: context, sync: sync)
            restoreStatusMessage = summary.displayText
            return true
        } catch {
            lastError = L.string("Recovery key is incorrect or the iCloud package cannot be opened.")
            return false
        }
    }

    func checkForRemoteVaultRestore(context: ModelContext, sync: CloudKitSyncService) async -> RemoteVaultRestoreCheck {
        do {
            var descriptor = FetchDescriptor<VaultManifest>()
            descriptor.fetchLimit = 1
            guard try context.fetch(descriptor).isEmpty else {
                return .noRemoteVault
            }

            guard let remoteManifest = await sync.fetchRemoteManifest() else {
                return .noRemoteVault
            }

            if try restoreRemoteManifestUsingAvailableKey(remoteManifest, context: context) {
                restoreStatusMessage = L.string("Existing iCloud vault found. Restoring encrypted index...")
                await pullCloudDecoyNotes(context: context, sync: sync)
                let summary = await downloadAllCloudAssets(context: context, sync: sync)
                restoreStatusMessage = summary.displayText
                return .restoredAutomatically(summary)
            }

            lastError = L.string("An existing iCloud vault was found. Restore it with iCloud Keychain or your recovery key before creating a new vault.")
            restoreStatusMessage = lastError
            return .needsRecoveryKey
        } catch {
            lastError = error.localizedDescription
            restoreStatusMessage = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func importData(
        _ data: Data,
        originalName: String,
        mimeType: String,
        source: String,
        kind: VaultItemKind,
        context: ModelContext,
        sync: CloudKitSyncService,
        folderId: String? = nil,
        syncAfterImport: Bool = true,
        saveImmediately: Bool = true
    ) async -> VaultImportResult {
        guard requireWriteAccess() else { return .failed }
        do {
            let importFingerprint = await VaultImportArtifactBuilder.fingerprint(for: data, kind: kind)
            if try isDuplicateImport(importFingerprint, context: context) {
                lastError = L.string("This item has already been imported.")
                return .skippedDuplicate
            }

            let prepared = try await VaultImportArtifactBuilder.prepare(
                data: data,
                originalName: originalName,
                mimeType: mimeType,
                source: source,
                kind: kind,
                importFingerprint: importFingerprint
            )

            let item = VaultItem(
                id: prepared.itemId,
                kind: kind,
                encryptedFilePath: prepared.encryptedFilePath,
                encryptedThumbPath: prepared.encryptedThumbPath,
                encryptedMetadata: prepared.encryptedMetadata,
                encryptedFileKey: prepared.encryptedFileKey,
                byteSize: Int64(data.count),
                folderId: folderId,
                importFingerprint: prepared.importFingerprint
            )
            context.insert(item)
            if saveImmediately {
                try context.save()
            }
            logger.info("Imported item \(prepared.itemId, privacy: .public), kind \(kind.rawValue, privacy: .public), file \(prepared.encryptedFilePath, privacy: .public), thumb \(prepared.encryptedThumbPath ?? "none", privacy: .public)")
            if syncAfterImport {
                _ = await sync.syncItem(item)
                try? context.save()
            }
            return .imported
        } catch {
            lastError = error.localizedDescription
            return .failed
        }
    }

    private func isDuplicateImport(_ importFingerprint: String?, context: ModelContext) throws -> Bool {
        guard let importFingerprint else { return false }
        let items = try context.fetch(FetchDescriptor<VaultItem>())
        return items.contains { item in
            item.deletedAt == nil
                && item.importFingerprint == importFingerprint
        }
    }

    func importLink(
        _ url: URL,
        title: String?,
        source: String,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async {
        guard requireWriteAccess() else { return }
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let displayName = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : url.host() ?? url.absoluteString
            let metadata = VaultMetadata(
                originalName: displayName,
                mimeType: "text/uri-list",
                source: source,
                note: "",
                importedAt: Date(),
                remoteURL: url.absoluteString,
                originalExtension: nil
            )
            let encryptedMetadata = try VaultCryptoService.encryptCodable(metadata, using: rootKey)
            let item = VaultItem(
                kind: .link,
                encryptedMetadata: encryptedMetadata,
                encryptedFileKey: Data(),
                byteSize: 0,
                assetState: .local
            )
            context.insert(item)
            try context.save()
            _ = await sync.syncItem(item)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func metadata(for item: VaultItem) -> VaultMetadata? {
        guard let rootKey = try? VaultCryptoService.ensureRootKey() else { return nil }
        return try? VaultCryptoService.decryptCodable(VaultMetadata.self, from: item.encryptedMetadata, using: rootKey)
    }

    func thumbnail(for item: VaultItem) -> UIImage? {
        guard let thumbPath = item.encryptedThumbPath,
              !thumbPath.isEmpty else {
            return nil
        }
        let cacheKey = "\(item.id):\(thumbPath):\(item.updatedAt.timeIntervalSince1970)"
        if let cached = thumbnailCache[cacheKey] {
            return cached
        }

        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let wrapped = try VaultCryptoService.unwrapFileKey(item.encryptedFileKey, rootKey: rootKey)
            let encrypted = try VaultFileStore.read(path: thumbPath)
            let data = try VaultCryptoService.decrypt(encrypted, using: wrapped)
            guard let image = UIImage(data: data) else {
                logger.error("Thumbnail data could not decode for item \(item.id, privacy: .public)")
                return nil
            }
            thumbnailCache[cacheKey] = image
            trimThumbnailCacheIfNeeded()
            return image
        } catch {
            logger.error("Thumbnail load failed for item \(item.id, privacy: .public), path \(thumbPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func trimThumbnailCacheIfNeeded() {
        guard thumbnailCache.count > 320 else { return }
        thumbnailCache.removeAll(keepingCapacity: true)
    }

    func decryptedTemporaryURL(for item: VaultItem) throws -> URL {
        let rootKey = try VaultCryptoService.ensureRootKey()
        let fileKey = try VaultCryptoService.unwrapFileKey(item.encryptedFileKey, rootKey: rootKey)
        let encrypted = try VaultFileStore.read(path: item.encryptedFilePath)
        let data = try VaultCryptoService.decrypt(encrypted, using: fileKey)
        let name = metadata(for: item)?.originalName ?? "\(item.id).bin"
        return try VaultFileStore.temporaryPlainURL(fileName: name, data: data)
    }

    func decryptedTemporaryURL(for item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async throws -> URL {
        if item.kind == .link, let urlString = metadata(for: item)?.remoteURL {
            return try VaultFileStore.temporaryPlainURL(
                fileName: "\(item.id).url",
                data: Data(urlString.utf8)
            )
        }

        if !VaultFileStore.fileExists(path: item.encryptedFilePath) || item.assetState == .cloudOnly {
            try await downloadOriginalIfNeeded(for: item, context: context, sync: sync)
        }
        return try decryptedTemporaryURL(for: item)
    }

    func decryptedLivePhotoResourceURLs(for item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async throws -> [URL] {
        let packageURL = try await decryptedTemporaryURL(for: item, context: context, sync: sync)
        let packageData = try Data(contentsOf: packageURL)
        let package = try PropertyListDecoder().decode(LivePhotoPackage.self, from: packageData)
        let stillURL = try VaultFileStore.temporaryPlainURL(fileName: package.stillFilename, data: package.stillData)
        let pairedVideoURL = try VaultFileStore.temporaryPlainURL(fileName: package.pairedVideoFilename, data: package.pairedVideoData)
        return [stillURL, pairedVideoURL]
    }

    func decryptedTemporaryURLs(for items: [VaultItem], context: ModelContext, sync: CloudKitSyncService) async -> [URL] {
        var urls: [URL] = []
        for item in items where item.deletedAt == nil {
            if item.kind == .link,
               let urlString = metadata(for: item)?.remoteURL,
               let url = URL(string: urlString) {
                urls.append(url)
                continue
            }

            if let url = try? await decryptedTemporaryURL(for: item, context: context, sync: sync) {
                urls.append(url)
            }
        }
        return urls
    }

    func toggleFavorite(_ item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        item.isFavorite.toggle()
        item.updatedAt = Date()
        item.localRevision += 1
        item.syncStatus = .pending
        try? context.save()
        _ = await sync.syncItem(item)
        try? context.save()
    }

    func rename(_ item: VaultItem, to name: String, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            guard var metadata = metadata(for: item) else { return }
            let existingExtension = metadata.originalExtension?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let submittedExtension = (trimmed as NSString).pathExtension
            let displayName: String
            if submittedExtension.isEmpty, !existingExtension.isEmpty {
                displayName = (trimmed as NSString).appendingPathExtension(existingExtension) ?? trimmed
            } else {
                displayName = trimmed
            }

            metadata.originalName = displayName
            metadata.originalExtension = (displayName as NSString).pathExtension
            item.encryptedMetadata = try VaultCryptoService.encryptCodable(metadata, using: rootKey)
            item.updatedAt = Date()
            item.localRevision += 1
            item.syncStatus = .pending
            try context.save()
            _ = await sync.syncItem(item)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func permanentlyDelete(_ item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        guard await sync.deleteItem(item) else {
            item.syncStatus = .failed
            try? context.save()
            lastError = sync.lastSyncError ?? L.string("iCloud delete failed. Local encrypted data was kept.")
            return
        }

        VaultFileStore.remove(path: item.encryptedFilePath)
        VaultFileStore.remove(path: item.encryptedThumbPath)
        context.delete(item)
        try? context.save()
    }

    func deleteImmediately(_ item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        item.deletedAt = item.deletedAt ?? Date()
        item.updatedAt = Date()
        item.localRevision += 1
        item.syncStatus = .pending
        let encryptedFilePath = item.encryptedFilePath
        let encryptedThumbPath = item.encryptedThumbPath
        try? context.save()
        VaultFileStore.remove(path: item.encryptedFilePath)
        VaultFileStore.remove(path: item.encryptedThumbPath)

        // 删除体验必须先本地生效；iCloud 墓碑记录放到后台同步，避免 CloudKit 慢时卡住界面。
        Task { @MainActor in
            let success = await sync.syncItem(item)
            if !success {
                item.syncStatus = .pending
                item.lastSyncError = sync.lastSyncError
            }
            try? context.save()
            VaultFileStore.remove(path: encryptedFilePath)
            VaultFileStore.remove(path: encryptedThumbPath)
        }
    }

    func deleteImmediately(_ items: [VaultItem], context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess(), !items.isEmpty else { return }
        let deletionTargets = items
            .filter { $0.deletedAt == nil }
            .map { item in
                (item: item, encryptedFilePath: item.encryptedFilePath, encryptedThumbPath: item.encryptedThumbPath)
            }
        guard !deletionTargets.isEmpty else { return }

        let now = Date()
        for target in deletionTargets {
            target.item.deletedAt = now
            target.item.updatedAt = now
            target.item.localRevision += 1
            target.item.syncStatus = .pending
        }
        try? context.save()

        for target in deletionTargets {
            VaultFileStore.remove(path: target.encryptedFilePath)
            VaultFileStore.remove(path: target.encryptedThumbPath)
        }

        // 批量删除只启动一个后台同步任务，避免大量照片删除时同时创建很多 CloudKit 请求。
        Task { @MainActor in
            for target in deletionTargets {
                let success = await sync.syncItem(target.item)
                if !success {
                    target.item.syncStatus = .pending
                    target.item.lastSyncError = sync.lastSyncError
                }
                VaultFileStore.remove(path: target.encryptedFilePath)
                VaultFileStore.remove(path: target.encryptedThumbPath)
            }
            try? context.save()
        }
    }

    func createFolder(named name: String, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let encryptedName = try VaultCryptoService.encryptString(trimmed, using: rootKey)
            let folder = VaultFolder(encryptedName: encryptedName, sortOrder: Int(Date().timeIntervalSince1970))
            context.insert(folder)
            try context.save()
            _ = await sync.syncFolder(folder)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func folderName(_ folder: VaultFolder) -> String {
        guard let rootKey = try? VaultCryptoService.ensureRootKey(),
              let name = try? VaultCryptoService.decryptString(folder.encryptedName, using: rootKey) else {
            return L.string("Untitled Album")
        }
        return name
    }

    func move(_ item: VaultItem, to folder: VaultFolder?, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        item.folderId = folder?.id
        item.updatedAt = Date()
        item.localRevision += 1
        item.syncStatus = .pending
        try? context.save()
        _ = await sync.syncItem(item)
        try? context.save()
    }

    func ensureInnerVaultFolder(context: ModelContext, sync: CloudKitSyncService) async -> VaultFolder? {
        guard requireWriteAccess() else { return nil }
        do {
            let innerVaultFolderId = Self.innerVaultFolderId
            let descriptor = FetchDescriptor<VaultFolder>(
                predicate: #Predicate<VaultFolder> { folder in
                    folder.id == innerVaultFolderId
                }
            )
            if let existing = try context.fetch(descriptor).first {
                if existing.deletedAt != nil {
                    existing.deletedAt = nil
                    existing.updatedAt = Date()
                    existing.localRevision += 1
                    existing.syncStatus = .pending
                    try context.save()
                    _ = await sync.syncFolder(existing)
                    try? context.save()
                }
                return existing
            }

            let rootKey = try VaultCryptoService.ensureRootKey()
            let encryptedName = try VaultCryptoService.encryptString("墨层", using: rootKey)
            let folder = VaultFolder(
                id: Self.innerVaultFolderId,
                encryptedName: encryptedName,
                sortOrder: Int.max
            )
            context.insert(folder)
            try context.save()
            _ = await sync.syncFolder(folder)
            try? context.save()
            return folder
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func moveToInnerVault(_ items: [VaultItem], context: ModelContext, sync: CloudKitSyncService) async -> Bool {
        guard await ensureInnerVaultFolder(context: context, sync: sync) != nil else { return false }
        return await move(items, toFolderId: Self.innerVaultFolderId, context: context, sync: sync)
    }

    @discardableResult
    func moveOutOfInnerVault(_ items: [VaultItem], context: ModelContext, sync: CloudKitSyncService) async -> Bool {
        await move(items, toFolderId: nil, context: context, sync: sync)
    }

    @discardableResult
    func move(_ items: [VaultItem], toFolderId folderId: String?, context: ModelContext, sync: CloudKitSyncService) async -> Bool {
        guard requireWriteAccess(), !items.isEmpty else { return false }
        var didMove = false
        for item in items where item.deletedAt == nil {
            item.folderId = folderId
            item.updatedAt = Date()
            item.localRevision += 1
            item.syncStatus = .pending
            didMove = true
        }
        guard didMove else { return false }
        try? context.save()
        for item in items where item.deletedAt == nil {
            _ = await sync.syncItem(item)
        }
        try? context.save()
        return true
    }

    func renameFolder(_ folder: VaultFolder, to name: String, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            folder.encryptedName = try VaultCryptoService.encryptString(trimmed, using: rootKey)
            folder.updatedAt = Date()
            folder.localRevision += 1
            folder.syncStatus = .pending
            try context.save()
            _ = await sync.syncFolder(folder)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteFolder(_ folder: VaultFolder, items: [VaultItem], context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        for item in items where item.folderId == folder.id {
            item.folderId = nil
            item.updatedAt = Date()
            item.localRevision += 1
            item.syncStatus = .pending
        }
        folder.deletedAt = Date()
        folder.updatedAt = Date()
        folder.localRevision += 1
        folder.syncStatus = .pending
        try? context.save()

        _ = await sync.syncFolder(folder)
        for item in items where item.syncStatus == .pending {
            _ = await sync.syncItem(item)
        }
        try? context.save()
    }

    func decoyNotePayload(for note: DecoyNoteRecord) -> DecoyNotePayload? {
        guard let rootKey = try? VaultCryptoService.ensureRootKey() else { return nil }
        return try? VaultCryptoService.decryptCodable(DecoyNotePayload.self, from: note.encryptedPayload, using: rootKey)
    }

    func createDecoyNote(
        id: String = UUID().uuidString,
        payload: DecoyNotePayload,
        isPinned: Bool = false,
        sortOrder: Double = Date().timeIntervalSince1970,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async {
        guard requireWriteAccess() else { return }
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let encryptedPayload = try VaultCryptoService.encryptCodable(payload, using: rootKey)
            let note = DecoyNoteRecord(id: id, encryptedPayload: encryptedPayload, isPinned: isPinned, sortOrder: sortOrder)
            context.insert(note)
            try context.save()
            _ = await sync.syncDecoyNote(note)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateDecoyNote(
        _ note: DecoyNoteRecord,
        payload: DecoyNotePayload,
        isPinned: Bool,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async {
        guard requireWriteAccess() else { return }
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            note.encryptedPayload = try VaultCryptoService.encryptCodable(payload, using: rootKey)
            note.isPinned = isPinned
            note.updatedAt = Date()
            note.localRevision += 1
            note.syncStatus = .pending
            note.lastSyncError = nil
            try context.save()
            _ = await sync.syncDecoyNote(note)
            try? context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func toggleDecoyTodo(
        _ note: DecoyNoteRecord,
        todoId: String,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async {
        guard requireWriteAccess() else { return }
        guard var payload = decoyNotePayload(for: note),
              let index = payload.todos.firstIndex(where: { $0.id == todoId }) else {
            return
        }
        payload.todos[index].done.toggle()
        await updateDecoyNote(note, payload: payload, isPinned: note.isPinned, context: context, sync: sync)
    }

    func toggleDecoyPin(_ note: DecoyNoteRecord, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        guard let payload = decoyNotePayload(for: note) else { return }
        await updateDecoyNote(note, payload: payload, isPinned: !note.isPinned, context: context, sync: sync)
    }

    func deleteDecoyNote(_ note: DecoyNoteRecord, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        note.deletedAt = Date()
        note.updatedAt = Date()
        note.localRevision += 1
        note.syncStatus = .pending
        note.lastSyncError = nil
        try? context.save()
        _ = await sync.syncDecoyNote(note)
        try? context.save()
    }

    func reorderDecoyNotes(_ notes: [DecoyNoteRecord], from source: IndexSet, to destination: Int, context: ModelContext, sync: CloudKitSyncService) async {
        guard requireWriteAccess() else { return }
        var reordered = notes
        reordered.move(fromOffsets: source, toOffset: destination)
        let now = Date()
        for (index, note) in reordered.enumerated() {
            note.sortOrder = Double(reordered.count - index)
            note.updatedAt = now
            note.localRevision += 1
            note.syncStatus = .pending
        }
        try? context.save()
        for note in reordered {
            _ = await sync.syncDecoyNote(note)
        }
        try? context.save()
    }

    func ensureDefaultDecoyNotes(_ defaults: [(id: String, payload: DecoyNotePayload, isPinned: Bool)], context: ModelContext, sync: CloudKitSyncService) async {
        guard allowsVaultWrites else { return }
        do {
            var descriptor = FetchDescriptor<DecoyNoteRecord>()
            descriptor.fetchLimit = 1
            guard try context.fetch(descriptor).isEmpty else { return }

            let baseSort = Date().timeIntervalSince1970
            for (index, item) in defaults.enumerated() {
                await createDecoyNote(
                    id: item.id,
                    payload: item.payload,
                    isPinned: item.isPinned,
                    sortOrder: baseSort - Double(index),
                    context: context,
                    sync: sync
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pullCloudDecoyNotes(context: ModelContext, sync: CloudKitSyncService) async {
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let remoteRecords = await sync.fetchRemoteDecoyNotes()
            let existing = try context.fetch(FetchDescriptor<DecoyNoteRecord>())
            var notesById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

            for record in remoteRecords {
                guard let noteId = record["noteId"] as? String else { continue }
                let encryptedPayload = record["encryptedPayload"] as? Data ?? Data()
                guard (try? VaultCryptoService.decryptCodable(DecoyNotePayload.self, from: encryptedPayload, using: rootKey)) != nil else {
                    continue
                }
                let remoteUpdatedAt = record["updatedAt"] as? Date ?? .distantPast
                let remoteRevision = record["localRevision"] as? Int ?? 1

                if let note = notesById[noteId] {
                    guard VaultRemoteMergePolicy.shouldApplyRemote(
                        remoteUpdatedAt: remoteUpdatedAt,
                        remoteRevision: remoteRevision,
                        localUpdatedAt: note.updatedAt,
                        localRevision: note.localRevision,
                        localSyncStatus: note.syncStatus
                    ) else { continue }
                    note.encryptedPayload = encryptedPayload
                    note.isPinned = (record["isPinned"] as? Int ?? (note.isPinned ? 1 : 0)) == 1
                    note.sortOrder = record["sortOrder"] as? Double ?? note.sortOrder
                    note.createdAt = record["createdAt"] as? Date ?? note.createdAt
                    note.updatedAt = remoteUpdatedAt
                    note.deletedAt = record["deletedAt"] as? Date
                    note.localRevision = remoteRevision
                    note.cloudRecordName = record.recordID.recordName
                    note.syncStatus = .synced
                    note.lastSyncError = nil
                } else {
                    let note = DecoyNoteRecord(
                        id: noteId,
                        encryptedPayload: encryptedPayload,
                        isPinned: (record["isPinned"] as? Int ?? 0) == 1,
                        sortOrder: record["sortOrder"] as? Double ?? remoteUpdatedAt.timeIntervalSince1970
                    )
                    note.createdAt = record["createdAt"] as? Date ?? Date()
                    note.updatedAt = remoteUpdatedAt
                    note.deletedAt = record["deletedAt"] as? Date
                    note.localRevision = remoteRevision
                    note.cloudRecordName = record.recordID.recordName
                    note.syncStatus = .synced
                    note.lastSyncError = nil
                    context.insert(note)
                    notesById[noteId] = note
                }
            }
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func syncPendingDecoyNotes(context: ModelContext, sync: CloudKitSyncService) async {
        guard allowsVaultWrites else { return }
        do {
            let notes = try context.fetch(FetchDescriptor<DecoyNoteRecord>())
            for note in notes where note.syncStatus != .synced {
                _ = await sync.syncDecoyNote(note)
            }
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func syncPendingChanges(context: ModelContext, sync: CloudKitSyncService, allowsCloudSync: Bool = true) async {
        guard allowsCloudSync, allowsVaultWrites else { return }
        await syncChanges(context: context, sync: sync, forceItems: false)
    }

    @discardableResult
    func syncCloudToLocal(
        context: ModelContext,
        sync: CloudKitSyncService,
        allowsCloudSync: Bool = true,
        allowsCloudWrite: Bool? = nil,
        downloadsOriginals: Bool = true
    ) async -> CloudAssetDownloadSummary {
        guard allowsCloudSync else { return CloudAssetDownloadSummary() }
        let canWriteCloud = allowsCloudWrite ?? allowsCloudSync

        let indexedCount = await pullCloudIndex(context: context, sync: sync, allowsCloudSync: allowsCloudSync)
        await pullCloudDecoyNotes(context: context, sync: sync)
        await syncPendingChanges(context: context, sync: sync, allowsCloudSync: canWriteCloud)

        guard downloadsOriginals else {
            let summary = CloudAssetDownloadSummary(indexedItems: indexedCount)
            restoreStatusMessage = summary.displayText
            return summary
        }

        return await downloadMissingCloudAssets(context: context, sync: sync, indexedItems: indexedCount)
    }

    @discardableResult
    func backupAllFilesToCloud(context: ModelContext, sync: CloudKitSyncService, allowsCloudSync: Bool = true) async -> CloudSyncRunSummary? {
        guard allowsCloudSync, allowsVaultWrites else {
            lastError = L.string("Renew Pro to use encrypted iCloud backup and multi-device sync.")
            sync.clearLogs()
            sync.beginSyncRun(itemCount: 0, folderCount: 0, decoyNoteCount: 0, manifestCount: 0)
            sync.recordItemSync(success: false, failure: lastError)
            sync.finishSyncRun()
            return sync.lastRunSummary
        }
        await syncChanges(context: context, sync: sync, forceItems: true, manualRun: true)
        return sync.lastRunSummary
    }

    @discardableResult
    func pullCloudIndex(context: ModelContext, sync: CloudKitSyncService, allowsCloudSync: Bool = true) async -> Int {
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            await pullCloudFolders(context: context, sync: sync)
            let remoteRecords = await sync.fetchRemoteItems()
            let existingItems = try context.fetch(FetchDescriptor<VaultItem>())
            var itemsById = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
            var indexedCount = 0

            for record in remoteRecords {
                guard let itemId = record["itemId"] as? String else {
                    continue
                }

                let kind = VaultItemKind(rawValue: record["type"] as? String ?? "") ?? .other
                let encryptedMetadata = record["encryptedMetadata"] as? Data ?? Data()
                guard (try? VaultCryptoService.decryptCodable(VaultMetadata.self, from: encryptedMetadata, using: rootKey)) != nil else {
                    continue
                }
                indexedCount += 1
                let encryptedFileKey = record["encryptedFileKey"] as? Data ?? Data()
                let byteSize = record["byteSize"] as? Int64 ?? 0
                let folderId = record["folderId"] as? String
                let remoteDeletedAt = record["deletedAt"] as? Date
                let remoteUpdatedAt = record["updatedAt"] as? Date ?? .distantPast
                let remoteRevision = record["localRevision"] as? Int ?? 1

                if let existing = itemsById[itemId] {
                    guard VaultRemoteMergePolicy.shouldApplyRemote(
                        remoteUpdatedAt: remoteUpdatedAt,
                        remoteRevision: remoteRevision,
                        localUpdatedAt: existing.updatedAt,
                        localRevision: existing.localRevision,
                        localSyncStatus: existing.syncStatus
                    ) else { continue }
                    existing.kindRawValue = kind.rawValue
                    existing.encryptedMetadata = encryptedMetadata
                    existing.encryptedFileKey = encryptedFileKey
                    existing.byteSize = byteSize
                    existing.folderId = folderId
                    existing.isFavorite = (record["favorite"] as? Int ?? (existing.isFavorite ? 1 : 0)) == 1
                    existing.deletedAt = remoteDeletedAt
                    existing.localRevision = remoteRevision
                    existing.importFingerprint = record["importFingerprint"] as? String
                    existing.cloudRecordName = record.recordID.recordName
                    existing.syncStatus = .synced
                    existing.lastSyncError = nil
                    existing.updatedAt = remoteUpdatedAt
                    if !VaultFileStore.fileExists(path: existing.encryptedFilePath), kind != .link {
                        existing.assetState = .cloudOnly
                    }
                } else {
                    let item = VaultItem(
                        id: itemId,
                        kind: kind,
                        encryptedFilePath: "",
                        encryptedThumbPath: nil,
                        encryptedMetadata: encryptedMetadata,
                        encryptedFileKey: encryptedFileKey,
                        byteSize: byteSize,
                        folderId: folderId,
                        assetState: kind == .link ? .local : .cloudOnly,
                        cloudRecordName: record.recordID.recordName,
                        importFingerprint: record["importFingerprint"] as? String
                    )
                    item.createdAt = record["createdAt"] as? Date ?? Date()
                    item.updatedAt = remoteUpdatedAt
                    item.deletedAt = remoteDeletedAt
                    item.isFavorite = (record["favorite"] as? Int ?? 0) == 1
                    item.localRevision = remoteRevision
                    item.syncStatus = .synced
                    item.lastSyncError = nil
                    context.insert(item)
                    itemsById[itemId] = item
                }
            }
            _ = rootKey
            try context.save()
            return indexedCount
        } catch {
            lastError = error.localizedDescription
            return 0
        }
    }

    func downloadOriginalIfNeeded(for item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async throws {
        guard item.kind != .link else { return }
        if VaultFileStore.fileExists(path: item.encryptedFilePath), item.assetState == .local {
            return
        }

        let assets = await sync.downloadAssets(for: item)
        guard let fileURL = assets.fileURL else {
            throw VaultCryptoService.CryptoError.missingRootKey
        }
        item.encryptedFilePath = try VaultFileStore.copyEncryptedObject(from: fileURL, itemId: item.id)
        if let thumbURL = assets.thumbURL {
            item.encryptedThumbPath = try? VaultFileStore.copyEncryptedThumb(from: thumbURL, itemId: item.id)
        }
        item.assetState = .local
        item.downloadedAt = Date()
        item.lastDownloadError = nil
        try context.save()
    }

    @discardableResult
    func downloadAllCloudAssets(context: ModelContext, sync: CloudKitSyncService) async -> CloudAssetDownloadSummary {
        let indexedItems = await pullCloudIndex(context: context, sync: sync)
        return await downloadMissingCloudAssets(context: context, sync: sync, indexedItems: indexedItems)
    }

    @discardableResult
    private func downloadMissingCloudAssets(
        context: ModelContext,
        sync: CloudKitSyncService,
        indexedItems: Int
    ) async -> CloudAssetDownloadSummary {
        var summary = CloudAssetDownloadSummary(indexedItems: indexedItems)
        do {
            let descriptor = FetchDescriptor<VaultItem>()
            let items = try context.fetch(descriptor)
            let candidates = items.filter { VaultCloudAssetDownloadPolicy.shouldDownload($0) }
            summary.total = candidates.count
            sync.appendLog("Starting full iCloud asset download count=\(candidates.count)")

            for item in candidates {
                do {
                    try await downloadOriginalIfNeeded(for: item, context: context, sync: sync)
                    summary.succeeded += 1
                } catch {
                    item.assetState = .failed
                    item.lastDownloadError = error.localizedDescription
                    summary.failed += 1
                    summary.failureMessages.append(error.localizedDescription)
                    sync.appendLog("Full asset download failed id=\(item.id) error=\(error.localizedDescription)")
                }
            }

            try context.save()
            sync.appendLog("Finished full iCloud asset download success=\(summary.succeeded) failed=\(summary.failed) total=\(summary.total)")
        } catch {
            summary.failed += 1
            summary.failureMessages.append(error.localizedDescription)
            lastError = error.localizedDescription
            sync.appendLog("Full iCloud asset download failed: \(error.localizedDescription)")
        }

        restoreStatusMessage = summary.displayText
        return summary
    }

    private func repairStoredFileReferences(context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<VaultItem>())
        var repairedCount = 0
        for item in items {
            let normalizedFilePath = VaultFileStore.normalizedStoredPath(item.encryptedFilePath) ?? item.encryptedFilePath
            if normalizedFilePath != item.encryptedFilePath {
                item.encryptedFilePath = normalizedFilePath
                repairedCount += 1
            }

            let normalizedThumbPath = VaultFileStore.normalizedStoredPath(item.encryptedThumbPath)
            if normalizedThumbPath != item.encryptedThumbPath {
                item.encryptedThumbPath = normalizedThumbPath
                repairedCount += 1
            }
        }

        if repairedCount > 0 {
            logger.info("Repaired \(repairedCount, privacy: .public) persisted vault file references")
            try context.save()
        }
    }

    private func repairMissingVideoThumbnails(context: ModelContext) async throws {
        let items = try context.fetch(FetchDescriptor<VaultItem>())
        var repairedCount = 0

        for item in items where shouldRepairVideoThumbnail(item) {
            guard let encryptedThumbPath = await makeEncryptedVideoThumbnail(for: item) else {
                continue
            }
            item.encryptedThumbPath = encryptedThumbPath
            item.updatedAt = Date()
            item.localRevision += 1
            item.syncStatus = .pending
            repairedCount += 1
        }

        if repairedCount > 0 {
            logger.info("Generated missing video thumbnails for \(repairedCount, privacy: .public) vault items")
            try context.save()
        }
    }

    private func shouldRepairVideoThumbnail(_ item: VaultItem) -> Bool {
        guard item.deletedAt == nil,
              item.kind == .video,
              !item.encryptedFilePath.isEmpty,
              VaultFileStore.fileExists(path: item.encryptedFilePath) else {
            return false
        }

        guard let thumbPath = item.encryptedThumbPath,
              !thumbPath.isEmpty else {
            return true
        }

        return !VaultFileStore.fileExists(path: thumbPath)
    }

    private func makeEncryptedVideoThumbnail(for item: VaultItem) async -> String? {
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            let fileKey = try VaultCryptoService.unwrapFileKey(item.encryptedFileKey, rootKey: rootKey)
            let encryptedFile = try VaultFileStore.read(path: item.encryptedFilePath)
            let data = try VaultCryptoService.decrypt(encryptedFile, using: fileKey)
            let metadata = try? VaultCryptoService.decryptCodable(
                VaultMetadata.self,
                from: item.encryptedMetadata,
                using: rootKey
            )
            guard let thumbData = await makeThumbnailData(
                from: data,
                kind: .video,
                originalName: metadata?.originalName ?? "",
                mimeType: metadata?.mimeType ?? ""
            ) else {
                return nil
            }

            let encryptedThumb = try VaultCryptoService.encrypt(thumbData, using: fileKey)
            return try VaultFileStore.writeEncryptedThumb(encryptedThumb, itemId: item.id)
        } catch {
            logger.error("Video thumbnail repair failed for item \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func syncChanges(context: ModelContext, sync: CloudKitSyncService, forceItems: Bool, manualRun: Bool = false) async {
        do {
            let manifests = try context.fetch(FetchDescriptor<VaultManifest>())
            let folders = try context.fetch(FetchDescriptor<VaultFolder>())
            let decoyNotes = try context.fetch(FetchDescriptor<DecoyNoteRecord>())
            let items = try context.fetch(FetchDescriptor<VaultItem>())

            let manifestsToSync = manifests.filter { forceItems || $0.syncStatus != .synced || !VaultCryptoService.canRestoreRootKey(from: $0.encryptedRootKeyPackage) }
            let foldersToSync = folders.filter { forceItems || $0.syncStatus != .synced }
            let decoyNotesToSync = decoyNotes.filter { forceItems || $0.syncStatus != .synced }
            let itemsToSync = items.filter { forceItems || $0.syncStatus != .synced }

            if manualRun {
                sync.clearLogs()
                sync.beginSyncRun(
                    itemCount: itemsToSync.count,
                    folderCount: foldersToSync.count,
                    decoyNoteCount: decoyNotesToSync.count,
                    manifestCount: manifestsToSync.count
                )

                guard await sync.runWritableProbe() else {
                    sync.recordItemSync(success: false, failure: sync.lastSyncError)
                    sync.finishSyncRun()
                    return
                }
            }

            for manifest in manifests {
                if !VaultCryptoService.canRestoreRootKey(from: manifest.encryptedRootKeyPackage) {
                    manifest.encryptedRootKeyPackage = try VaultCryptoService.makeRootKeyPackage()
                    manifest.updatedAt = Date()
                    manifest.syncStatus = .pending
                }
                guard forceItems || manifest.syncStatus != .synced else { continue }
                let success = await sync.syncManifest(manifest)
                if manualRun {
                    sync.recordManifestSync(success: success, failure: success ? nil : sync.lastSyncError)
                }
            }

            for folder in foldersToSync {
                let success = await sync.syncFolder(folder)
                if manualRun {
                    sync.recordFolderSync(success: success, failure: success ? nil : sync.lastSyncError)
                }
            }

            for note in decoyNotesToSync {
                let success = await sync.syncDecoyNote(note)
                if manualRun {
                    sync.recordDecoyNoteSync(success: success, failure: success ? nil : note.lastSyncError ?? sync.lastSyncError)
                }
            }

            for item in itemsToSync {
                let success = await sync.syncItem(item)
                if manualRun {
                    sync.recordItemSync(success: success, failure: success ? nil : item.lastSyncError ?? sync.lastSyncError)
                }
            }
            try context.save()
            if manualRun {
                sync.finishSyncRun()
            }
        } catch {
            lastError = error.localizedDescription
            if manualRun {
                sync.recordItemSync(success: false, failure: lastError)
                sync.finishSyncRun()
            }
        }
    }

    private func restoreRemoteManifestUsingAvailableKey(_ record: CKRecord, context: ModelContext) throws -> Bool {
        let package = record["encryptedRootKeyPackage"] as? Data ?? Data()
        if !VaultCryptoService.hasRootKey() {
            _ = try? VaultCryptoService.restoreRootKeyFromICloudKeychain()
        }
        let encryptedVaultName = record["encryptedVaultName"] as? Data ?? Data()
        let rootKey = VaultCryptoService.hasRootKey() ? try? VaultCryptoService.ensureRootKey() : nil
        let canOpenWithLocalRootKey = rootKey.flatMap { try? VaultCryptoService.decryptString(encryptedVaultName, using: $0) } != nil
        guard canOpenWithLocalRootKey || VaultCryptoService.canRestoreRootKey(from: package) else {
            return false
        }

        let manifest = makeManifest(from: record)
        context.insert(manifest)
        try context.save()
        return true
    }

    private func pullCloudFolders(context: ModelContext, sync: CloudKitSyncService) async {
        do {
            let remoteRecords = await sync.fetchRemoteFolders()
            let existingFolders = try context.fetch(FetchDescriptor<VaultFolder>())
            var foldersById = Dictionary(uniqueKeysWithValues: existingFolders.map { ($0.id, $0) })

            for record in remoteRecords {
                guard let folderId = record["folderId"] as? String else { continue }
                let encryptedName = record["encryptedName"] as? Data ?? Data()
                let sortOrder = record["sortOrder"] as? Int ?? 0
                let updatedAt = record["updatedAt"] as? Date ?? Date()
                let deletedAt = record["deletedAt"] as? Date
                let localRevision = record["localRevision"] as? Int ?? 1

                if let existing = foldersById[folderId] {
                    guard VaultRemoteMergePolicy.shouldApplyRemote(
                        remoteUpdatedAt: updatedAt,
                        remoteRevision: localRevision,
                        localUpdatedAt: existing.updatedAt,
                        localRevision: existing.localRevision,
                        localSyncStatus: existing.syncStatus
                    ) else { continue }
                    existing.encryptedName = encryptedName
                    existing.sortOrder = sortOrder
                    existing.updatedAt = updatedAt
                    existing.deletedAt = deletedAt
                    existing.localRevision = localRevision
                    existing.cloudRecordName = record.recordID.recordName
                    existing.syncStatus = .synced
                } else {
                    let folder = VaultFolder(id: folderId, encryptedName: encryptedName, sortOrder: sortOrder)
                    folder.updatedAt = updatedAt
                    folder.deletedAt = deletedAt
                    folder.localRevision = localRevision
                    folder.cloudRecordName = record.recordID.recordName
                    folder.syncStatus = .synced
                    context.insert(folder)
                    foldersById[folderId] = folder
                }
            }
            try context.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func makeLocalManifest(rootKey: SymmetricKey) throws -> VaultManifest {
        try? VaultCryptoService.syncRootKeyToICloudKeychain()
        let name = try VaultCryptoService.encryptString("Private Vault", using: rootKey)
        let package = try VaultCryptoService.makeRootKeyPackage()
        return VaultManifest(id: UUID().uuidString, encryptedVaultName: name, encryptedRootKeyPackage: package)
    }

    private func makeManifest(from record: CKRecord) -> VaultManifest {
        let manifest = VaultManifest(
            id: record["vaultId"] as? String ?? record.recordID.recordName,
            encryptedVaultName: record["encryptedVaultName"] as? Data ?? Data(),
            encryptedRootKeyPackage: record["encryptedRootKeyPackage"] as? Data ?? Data()
        )
        manifest.schemaVersion = record["schemaVersion"] as? Int ?? 1
        manifest.updatedAt = record["updatedAt"] as? Date ?? Date()
        manifest.syncStatus = .synced
        return manifest
    }

    private func makeThumbnailData(
        from data: Data,
        kind: VaultItemKind,
        originalName: String = "",
        mimeType: String = ""
    ) async -> Data? {
        switch kind {
        case .image:
            guard let image = UIImage(data: data) else { return nil }
            return renderThumbnailData(from: image)
        case .livePhoto:
            guard let package = try? PropertyListDecoder().decode(LivePhotoPackage.self, from: data),
                  let image = UIImage(data: package.stillData) else {
                return nil
            }
            return renderThumbnailData(from: image)
        case .video:
            return await makeVideoThumbnailData(
                from: data,
                preferredExtension: videoFileExtension(originalName: originalName, mimeType: mimeType)
            )
        default:
            return nil
        }
    }

    private func makeVideoThumbnailData(from data: Data, preferredExtension: String?) async -> Data? {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(preferredExtension ?? "mov")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            let asset = AVURLAsset(url: temporaryURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity

            for time in videoThumbnailTimes {
                if let image = try? await generateImage(with: generator, at: time),
                   let data = renderThumbnailData(from: UIImage(cgImage: image)) {
                    return data
                }
            }

            return nil
        } catch {
            return nil
        }
    }

    private var videoThumbnailTimes: [CMTime] {
        [
            CMTime(seconds: 0, preferredTimescale: 600),
            CMTime(seconds: 0.1, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600),
            CMTime(seconds: 1, preferredTimescale: 600)
        ]
    }

    private func videoFileExtension(originalName: String, mimeType: String) -> String? {
        let nameExtension = (originalName as NSString).pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameExtension.isEmpty {
            return nameExtension.lowercased()
        }

        let mimeExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension
        return mimeExtension?.isEmpty == false ? mimeExtension : nil
    }

    private func generateImage(with generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile))
                }
            }
        }
    }

    private func renderThumbnailData(from image: UIImage) -> Data? {
        let target = CGSize(width: 320, height: 320)
        let renderer = UIGraphicsImageRenderer(size: target)
        let rendered = renderer.image { _ in
            let scale = max(target.width / image.size.width, target.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2)
            image.draw(in: CGRect(origin: origin, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.78)
    }
}
