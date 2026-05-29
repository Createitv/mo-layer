import Combine
import AVFoundation
import CloudKit
import CryptoKit
import Foundation
import OSLog
import SwiftData
import UIKit
import UniformTypeIdentifiers

@MainActor
final class VaultStore: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "VaultStore")
    private var thumbnailCache: [String: UIImage] = [:]
    @Published var lastError: String?

    func bootstrap(context: ModelContext, sync: CloudKitSyncService, allowsCloudSync: Bool = true) async {
        do {
            try VaultFileStore.prepareDirectories()
            try repairStoredFileReferences(context: context)
            try await repairMissingVideoThumbnails(context: context)

            var descriptor = FetchDescriptor<VaultManifest>()
            descriptor.fetchLimit = 1
            if try context.fetch(descriptor).isEmpty {
                if allowsCloudSync, let remoteManifest = await sync.fetchRemoteManifest() {
                    if try restoreRemoteManifestUsingAvailableKey(remoteManifest, context: context) {
                        await pullCloudIndex(context: context, sync: sync, allowsCloudSync: allowsCloudSync)
                    } else {
                        lastError = L.string("An existing iCloud vault was found. Restore it with iCloud Keychain or your recovery key before creating a new vault.")
                    }
                    return
                } else {
                    let rootKey = try VaultCryptoService.ensureRootKey()
                    let manifest = try makeLocalManifest(rootKey: rootKey)
                    context.insert(manifest)
                    try context.save()
                    if allowsCloudSync {
                        _ = await sync.syncManifest(manifest)
                    }
                    try? context.save()
                }
            }

            await syncPendingChanges(context: context, sync: sync, allowsCloudSync: allowsCloudSync)
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
            await pullCloudIndex(context: context, sync: sync)
            return true
        } catch {
            lastError = L.string("Recovery key is incorrect or the iCloud package cannot be opened.")
            return false
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
        sync: CloudKitSyncService
    ) async -> Bool {
        do {
            let importFingerprint = fingerprintIfNeeded(for: data, kind: kind)
            if try isDuplicateImport(importFingerprint, kind: kind, context: context) {
                lastError = L.string("This photo or video has already been imported.")
                return true
            }

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

            let item = VaultItem(
                id: itemId,
                kind: kind,
                encryptedFilePath: encryptedFilePath,
                encryptedThumbPath: encryptedThumbPath,
                encryptedMetadata: encryptedMetadata,
                encryptedFileKey: encryptedFileKey,
                byteSize: Int64(data.count),
                importFingerprint: importFingerprint
            )
            context.insert(item)
            try context.save()
            logger.info("Imported item \(itemId, privacy: .public), kind \(kind.rawValue, privacy: .public), file \(encryptedFilePath, privacy: .public), thumb \(encryptedThumbPath ?? "none", privacy: .public)")
            _ = await sync.syncItem(item)
            try? context.save()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func fingerprintIfNeeded(for data: Data, kind: VaultItemKind) -> String? {
        switch kind {
        case .image, .livePhoto, .video:
            VaultImportFingerprint.digest(for: data)
        case .audio, .document, .archive, .link, .other:
            nil
        }
    }

    private func isDuplicateImport(_ importFingerprint: String?, kind: VaultItemKind, context: ModelContext) throws -> Bool {
        guard let importFingerprint else { return false }
        let items = try context.fetch(FetchDescriptor<VaultItem>())
        return items.contains { item in
            item.deletedAt == nil
                && item.importFingerprint == importFingerprint
                && (item.kind == .image || item.kind == .video)
        }
    }

    func importLink(
        _ url: URL,
        title: String?,
        source: String,
        context: ModelContext,
        sync: CloudKitSyncService
    ) async {
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
        item.isFavorite.toggle()
        item.updatedAt = Date()
        item.localRevision += 1
        item.syncStatus = .pending
        try? context.save()
        _ = await sync.syncItem(item)
        try? context.save()
    }

    func permanentlyDelete(_ item: VaultItem, context: ModelContext, sync: CloudKitSyncService) async {
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
        _ = await sync.deleteItem(item)
        VaultFileStore.remove(path: item.encryptedFilePath)
        VaultFileStore.remove(path: item.encryptedThumbPath)
        context.delete(item)
        try? context.save()
    }

    func createFolder(named name: String, context: ModelContext, sync: CloudKitSyncService) async {
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
        item.folderId = folder?.id
        item.updatedAt = Date()
        item.localRevision += 1
        item.syncStatus = .pending
        try? context.save()
        _ = await sync.syncItem(item)
        try? context.save()
    }

    func renameFolder(_ folder: VaultFolder, to name: String, context: ModelContext, sync: CloudKitSyncService) async {
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

    func syncPendingChanges(context: ModelContext, sync: CloudKitSyncService, allowsCloudSync: Bool = true) async {
        guard allowsCloudSync else { return }
        await syncChanges(context: context, sync: sync, forceItems: false)
    }

    func backupAllFilesToCloud(context: ModelContext, sync: CloudKitSyncService, allowsCloudSync: Bool = true) async {
        guard allowsCloudSync else {
            lastError = L.string("Renew Pro to use encrypted iCloud backup and multi-device sync.")
            return
        }
        await syncChanges(context: context, sync: sync, forceItems: true)
    }

    func pullCloudIndex(context: ModelContext, sync: CloudKitSyncService, allowsCloudSync: Bool = true) async {
        guard allowsCloudSync else { return }
        do {
            let rootKey = try VaultCryptoService.ensureRootKey()
            await pullCloudFolders(context: context, sync: sync)
            let remoteRecords = await sync.fetchRemoteItems()
            let existingItems = try context.fetch(FetchDescriptor<VaultItem>())
            var itemsById = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })

            for record in remoteRecords {
                guard let itemId = record["itemId"] as? String else {
                    continue
                }

                let kind = VaultItemKind(rawValue: record["type"] as? String ?? "") ?? .other
                let encryptedMetadata = record["encryptedMetadata"] as? Data ?? Data()
                guard (try? VaultCryptoService.decryptCodable(VaultMetadata.self, from: encryptedMetadata, using: rootKey)) != nil else {
                    continue
                }
                let encryptedFileKey = record["encryptedFileKey"] as? Data ?? Data()
                let byteSize = record["byteSize"] as? Int64 ?? 0
                let folderId = record["folderId"] as? String
                let remoteDeletedAt = record["deletedAt"] as? Date

                if let existing = itemsById[itemId] {
                    existing.kindRawValue = kind.rawValue
                    existing.encryptedMetadata = encryptedMetadata
                    existing.encryptedFileKey = encryptedFileKey
                    existing.byteSize = byteSize
                    existing.folderId = folderId
                    existing.isFavorite = (record["favorite"] as? Int ?? (existing.isFavorite ? 1 : 0)) == 1
                    existing.deletedAt = remoteDeletedAt
                    existing.localRevision = record["localRevision"] as? Int ?? existing.localRevision
                    existing.importFingerprint = record["importFingerprint"] as? String
                    existing.cloudRecordName = record.recordID.recordName
                    existing.updatedAt = record["updatedAt"] as? Date ?? existing.updatedAt
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
                    item.updatedAt = record["updatedAt"] as? Date ?? Date()
                    item.deletedAt = remoteDeletedAt
                    item.isFavorite = (record["favorite"] as? Int ?? 0) == 1
                    item.localRevision = record["localRevision"] as? Int ?? item.localRevision
                    item.syncStatus = .synced
                    context.insert(item)
                    itemsById[itemId] = item
                }
            }
            _ = rootKey
            try context.save()
        } catch {
            lastError = error.localizedDescription
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

    private func syncChanges(context: ModelContext, sync: CloudKitSyncService, forceItems: Bool) async {
        do {
            let manifests = try context.fetch(FetchDescriptor<VaultManifest>())
            for manifest in manifests {
                if !VaultCryptoService.canRestoreRootKey(from: manifest.encryptedRootKeyPackage) {
                    manifest.encryptedRootKeyPackage = try VaultCryptoService.makeRootKeyPackage()
                    manifest.updatedAt = Date()
                    manifest.syncStatus = .pending
                }
                guard manifest.syncStatus != .synced else { continue }
                _ = await sync.syncManifest(manifest)
            }

            let folders = try context.fetch(FetchDescriptor<VaultFolder>())
            for folder in folders where folder.syncStatus != .synced {
                _ = await sync.syncFolder(folder)
            }

            let items = try context.fetch(FetchDescriptor<VaultItem>())
            for item in items where forceItems || item.syncStatus != .synced {
                _ = await sync.syncItem(item)
            }
            try context.save()
        } catch {
            lastError = error.localizedDescription
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
