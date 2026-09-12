import CryptoKit
import Foundation
import SwiftData

@MainActor
enum PhotoTransferStorage {
    static func item(id: String, context: ModelContext) throws -> VaultItem? {
        var descriptor = FetchDescriptor<VaultItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func verifiedFingerprint(item: VaultItem, rootKey: SymmetricKey) async throws -> String {
        guard item.deletedAt == nil, !item.encryptedFilePath.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        let path = item.encryptedFilePath
        let wrappedKey = item.encryptedFileKey
        let kind = item.kind
        return try await Task.detached(priority: .userInitiated) {
            let key = try VaultCryptoService.unwrapFileKey(wrappedKey, rootKey: rootKey)
            return try fingerprint(encrypted: VaultFileStore.read(path: path), fileKey: key, kind: kind)
        }.value
    }

    nonisolated static func fingerprint(encrypted: Data, fileKey: SymmetricKey, kind: VaultItemKind = .other) throws -> String {
        let bytes = try VaultCryptoService.decrypt(encrypted, using: fileKey)
        return try contentFingerprint(data: bytes, kind: kind)
    }

    nonisolated static func contentFingerprint(data: Data, kind: VaultItemKind) throws -> String {
        guard kind == .livePhoto else { return VaultImportFingerprint.digest(for: data) }
        // Property list serialization order may vary across processes; hash resource content.
        let package = try PropertyListDecoder().decode(LivePhotoPackage.self, from: data)
        guard !package.stillData.isEmpty, !package.pairedVideoData.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let parts = [VaultImportFingerprint.digest(for: package.stillData), VaultImportFingerprint.digest(for: package.pairedVideoData), package.stillFilename, package.pairedVideoFilename]
        return "live:" + VaultImportFingerprint.digest(for: try JSONSerialization.data(withJSONObject: parts))
    }

    /// Commit first, then return a receipt. A journal write failure can safely replay this ID.
    static func commit(data: Data, staged: StagedPhotoTransfer, entry: PhotoTransferEntry,
                       folderID: String?, context: ModelContext, rootKey: SymmetricKey) async throws -> PhotoTransferEntry {
        let kind = staged.kind
        let digest = try await Task.detached { try contentFingerprint(data: data, kind: kind) }.value
        var receipt = entry
        if let existing = try item(id: entry.vaultID, context: context) {
            guard try await verifiedFingerprint(item: existing, rootKey: rootKey) == digest else { throw CocoaError(.fileReadCorruptFile) }
            try context.save()
        } else {
            var duplicateQuery = FetchDescriptor<VaultItem>(predicate: #Predicate { $0.deletedAt == nil && $0.importFingerprint == digest })
            duplicateQuery.fetchLimit = 1
            if try !context.fetch(duplicateQuery).isEmpty {
                receipt.state = .duplicate // Never delete sources of unverified historical copies.
                receipt.error = nil
                return receipt
            }
            let reservation = try VaultStorageQuota.reserve(bytes: Int64(data.count), context: context)
            defer { VaultStorageQuota.release(reservation) }
            let prepared = try await VaultImportArtifactBuilder.prepare(data: data, originalName: staged.names[0],
                mimeType: staged.mimeType, source: "Photos", kind: staged.kind, importFingerprint: digest,
                capturedAt: staged.capturedAt, captureLocation: staged.location, itemID: entry.vaultID, rootKeyOverride: rootKey)
            let newItem = VaultItem(id: prepared.itemId, kind: staged.kind, encryptedFilePath: prepared.encryptedFilePath,
                encryptedThumbPath: prepared.encryptedThumbPath, encryptedMetadata: prepared.encryptedMetadata,
                encryptedFileKey: prepared.encryptedFileKey, byteSize: Int64(data.count), folderId: folderID, importFingerprint: digest)
            var inserted = false
            do {
                // Check bytes from disk using the persisted wrapped key, not the in-memory source.
                guard try await verifiedFingerprint(item: newItem, rootKey: rootKey) == digest else { throw CocoaError(.fileReadCorruptFile) }
                context.insert(newItem)
                inserted = true
                try context.save()
            } catch {
                if inserted { context.delete(newItem) }
                VaultFileStore.remove(path: prepared.encryptedFilePath)
                VaultFileStore.remove(path: prepared.encryptedThumbPath)
                throw error
            }
        }
        receipt.fingerprint = digest
        receipt.sourceModifiedAt = staged.modifiedAt
        receipt.state = staged.preservesAllResources ? .verified : .savedKeepingOriginal
        receipt.error = nil
        return receipt
    }
}
