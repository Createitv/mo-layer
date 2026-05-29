import CloudKit
import Combine
import Foundation
import SwiftData

enum CloudSyncState: Equatable {
    case checking
    case available
    case unavailable(String)
    case syncing
    case synced(Date)
    case failed(String)

    var title: String {
        switch self {
        case .checking: L.string("Checking iCloud")
        case .available: L.string("iCloud Available")
        case .unavailable: L.string("Local Protection")
        case .syncing: L.string("Syncing")
        case .synced: L.string("Synced")
        case .failed: L.string("Sync Failed")
        }
    }

    var detail: String {
        switch self {
        case .checking: L.string("Checking CloudKit status")
        case .available: L.string("Encrypted metadata and files can sync to your iCloud")
        case .unavailable(let reason): reason
        case .syncing: L.string("Uploading encrypted metadata and files")
        case .synced(let date): L.format("Last synced %@", date.formatted(date: .omitted, time: .shortened))
        case .failed(let reason): reason
        }
    }
}

@MainActor
final class CloudKitSyncService: ObservableObject {
    @Published var state: CloudSyncState = .checking
    @Published var lastSyncError: String?

    private let container = CKContainer(identifier: "iCloud.app.landlady.www.privacy")
    private var database: CKDatabase {
        container.privateCloudDatabase
    }

    func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                state = .available
                lastSyncError = nil
            case .noAccount:
                state = .unavailable(L.string("Not signed into iCloud. Items remain encrypted locally."))
            case .restricted:
                state = .unavailable(L.string("This iCloud account is restricted."))
            case .couldNotDetermine:
                state = .unavailable(L.string("Unable to verify iCloud status."))
            case .temporarilyUnavailable:
                state = .unavailable(L.string("iCloud is temporarily unavailable."))
            @unknown default:
                state = .unavailable(L.string("Unknown iCloud status."))
            }
        } catch {
            state = .failed(error.localizedDescription)
            lastSyncError = error.localizedDescription
        }
    }

    func syncManifest(_ manifest: VaultManifest) async -> Bool {
        guard await ensureCloudAvailable() else {
            manifest.syncStatus = .pending
            return false
        }
        state = .syncing
        let recordID = CKRecord.ID(recordName: manifest.id)
        let record = CKRecord(recordType: "VaultManifest", recordID: recordID)
        record["vaultId"] = manifest.id
        record["schemaVersion"] = manifest.schemaVersion
        record["encryptedVaultName"] = manifest.encryptedVaultName
        record["encryptedRootKeyPackage"] = manifest.encryptedRootKeyPackage
        record["updatedAt"] = manifest.updatedAt

        do {
            _ = try await database.save(record)
            manifest.syncStatus = .synced
            state = .synced(Date())
            lastSyncError = nil
            return true
        } catch {
            manifest.syncStatus = .failed
            state = .failed(error.localizedDescription)
            lastSyncError = error.localizedDescription
            return false
        }
    }

    func fetchRemoteManifest() async -> CKRecord? {
        guard await ensureCloudAvailable() else { return nil }

        state = .syncing
        let records = await fetchRecords(recordType: "VaultManifest")
        let latest = records.max {
            ($0["updatedAt"] as? Date ?? .distantPast) < ($1["updatedAt"] as? Date ?? .distantPast)
        }
        state = .synced(Date())
        lastSyncError = nil
        return latest
    }

    func syncItem(_ item: VaultItem) async -> Bool {
        guard await ensureCloudAvailable() else {
            item.syncStatus = .pending
            return false
        }

        state = .syncing
        let fileURL = VaultFileStore.assetURL(for: item.encryptedFilePath)
        let requiresFileAsset = item.kind != .link && item.deletedAt == nil
        guard !requiresFileAsset || VaultFileStore.fileExists(path: item.encryptedFilePath) else {
            return failItemSync(item, reason: L.string("Local encrypted file is missing; cannot upload to iCloud."))
        }

        let recordID = CKRecord.ID(recordName: item.cloudRecordName ?? item.id)
        let record = CKRecord(recordType: "VaultItem", recordID: recordID)
        record["itemId"] = item.id
        record["type"] = item.kindRawValue
        record["encryptedMetadata"] = item.encryptedMetadata
        record["encryptedFileKey"] = item.encryptedFileKey
        record["byteSize"] = item.byteSize
        record["folderId"] = item.folderId
        record["favorite"] = item.isFavorite ? 1 : 0
        record["createdAt"] = item.createdAt
        record["updatedAt"] = item.updatedAt
        record["deletedAt"] = item.deletedAt
        record["localRevision"] = item.localRevision
        record["assetState"] = item.assetStateRawValue
        record["importFingerprint"] = item.importFingerprint

        if requiresFileAsset {
            record["fileAsset"] = CKAsset(fileURL: fileURL)
        }
        if let thumbPath = item.encryptedThumbPath, VaultFileStore.fileExists(path: thumbPath) {
            record["thumbAsset"] = CKAsset(fileURL: VaultFileStore.assetURL(for: thumbPath))
        }

        do {
            let saved = try await database.save(record)
            item.cloudRecordName = saved.recordID.recordName
            item.syncStatus = .synced
            state = .synced(Date())
            lastSyncError = nil
            return true
        } catch {
            item.syncStatus = .failed
            state = .failed(error.localizedDescription)
            lastSyncError = error.localizedDescription
            return false
        }
    }

    func fetchRemoteItems() async -> [CKRecord] {
        guard await ensureCloudAvailable() else { return [] }

        state = .syncing
        let records = await fetchRecords(recordType: "VaultItem")
        state = .synced(Date())
        lastSyncError = nil
        return records
    }

    func fetchRemoteFolders() async -> [CKRecord] {
        guard await ensureCloudAvailable() else { return [] }

        state = .syncing
        let records = await fetchRecords(recordType: "VaultFolder")
        state = .synced(Date())
        lastSyncError = nil
        return records
    }

    func downloadAssets(for item: VaultItem) async -> (fileURL: URL?, thumbURL: URL?) {
        guard await ensureCloudAvailable() else {
            item.assetState = .failed
            item.lastDownloadError = lastSyncError
            return (nil, nil)
        }

        state = .syncing
        item.assetState = .downloading
        let recordID = CKRecord.ID(recordName: item.cloudRecordName ?? item.id)
        do {
            let record = try await database.record(for: recordID)
            let fileURL = (record["fileAsset"] as? CKAsset)?.fileURL
            let thumbURL = (record["thumbAsset"] as? CKAsset)?.fileURL
            item.assetState = fileURL == nil && item.kind != .link ? .failed : .local
            item.lastDownloadError = item.assetState == .failed ? L.string("Original encrypted file was not found in iCloud.") : nil
            state = .synced(Date())
            lastSyncError = nil
            return (fileURL, thumbURL)
        } catch {
            item.assetState = .failed
            item.lastDownloadError = error.localizedDescription
            state = .failed(error.localizedDescription)
            lastSyncError = error.localizedDescription
            return (nil, nil)
        }
    }

    func deleteItem(_ item: VaultItem) async -> Bool {
        guard await ensureCloudAvailable() else {
            item.syncStatus = .pending
            return false
        }

        item.deletedAt = item.deletedAt ?? Date()
        item.updatedAt = Date()
        item.localRevision += 1
        item.syncStatus = .pending
        return await syncItem(item)
    }

    func syncFolder(_ folder: VaultFolder) async -> Bool {
        guard await ensureCloudAvailable() else {
            folder.syncStatus = .pending
            return false
        }

        state = .syncing
        let recordID = CKRecord.ID(recordName: folder.cloudRecordName ?? folder.id)
        let record = CKRecord(recordType: "VaultFolder", recordID: recordID)
        record["folderId"] = folder.id
        record["encryptedName"] = folder.encryptedName
        record["sortOrder"] = folder.sortOrder
        record["updatedAt"] = folder.updatedAt
        record["deletedAt"] = folder.deletedAt
        record["localRevision"] = folder.localRevision

        do {
            let saved = try await database.save(record)
            folder.cloudRecordName = saved.recordID.recordName
            folder.syncStatus = .synced
            state = .synced(Date())
            lastSyncError = nil
            return true
        } catch {
            folder.syncStatus = .failed
            state = .failed(error.localizedDescription)
            lastSyncError = error.localizedDescription
            return false
        }
    }

    private func ensureCloudAvailable() async -> Bool {
        switch state {
        case .available, .synced:
            return true
        case .checking, .failed, .unavailable:
            await checkAccountStatus()
            if case .available = state { return true }
            if case .synced = state { return true }
            return false
        case .syncing:
            return true
        }
    }

    private func failItemSync(_ item: VaultItem, reason: String) -> Bool {
        item.syncStatus = .failed
        state = .failed(reason)
        lastSyncError = reason
        return false
    }

    private func fetchRecords(recordType: String) async -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let (records, cursor) = await fetchRecords(query: query)
        guard let cursor else { return records }
        return await fetchRemainingRecords(cursor: cursor, accumulated: records)
    }

    private func fetchRecords(query: CKQuery) async -> ([CKRecord], CKQueryOperation.Cursor?) {
        await withCheckedContinuation { continuation in
            let operation = CKQueryOperation(query: query)
            configure(operation: operation, continuation: continuation)
            database.add(operation)
        }
    }

    private func fetchRecords(cursor: CKQueryOperation.Cursor) async -> ([CKRecord], CKQueryOperation.Cursor?) {
        await withCheckedContinuation { continuation in
            let operation = CKQueryOperation(cursor: cursor)
            configure(operation: operation, continuation: continuation)
            database.add(operation)
        }
    }

    private func fetchRemainingRecords(cursor: CKQueryOperation.Cursor, accumulated: [CKRecord]) async -> [CKRecord] {
        let (records, nextCursor) = await fetchRecords(cursor: cursor)
        let combined = accumulated + records
        guard let nextCursor else { return combined }
        return await fetchRemainingRecords(cursor: nextCursor, accumulated: combined)
    }

    private func configure(
        operation: CKQueryOperation,
        continuation: CheckedContinuation<([CKRecord], CKQueryOperation.Cursor?), Never>
    ) {
        var records: [CKRecord] = []
        operation.recordMatchedBlock = { _, result in
            if case .success(let record) = result {
                records.append(record)
            }
        }
        operation.queryResultBlock = { result in
            switch result {
            case .success(let cursor):
                continuation.resume(returning: (records, cursor))
            case .failure(let error):
                Task { @MainActor in
                    self.state = .failed(error.localizedDescription)
                    self.lastSyncError = error.localizedDescription
                }
                continuation.resume(returning: (records, nil))
            }
        }
    }
}
