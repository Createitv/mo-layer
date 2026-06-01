import CloudKit
import Combine
import Foundation
import OSLog
import SwiftData

struct CloudSyncLogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let message: String

    var displayText: String {
        "\(date.formatted(date: .omitted, time: .standard))  \(message)"
    }
}

struct CloudSyncRunSummary: Equatable {
    var startedAt = Date()
    var finishedAt: Date?
    var manifestTotal = 0
    var manifestSucceeded = 0
    var manifestFailed = 0
    var folderTotal = 0
    var folderSucceeded = 0
    var folderFailed = 0
    var decoyNoteTotal = 0
    var decoyNoteSucceeded = 0
    var decoyNoteFailed = 0
    var itemTotal = 0
    var itemSucceeded = 0
    var itemFailed = 0
    var failureMessages: [String] = []

    var totalSucceeded: Int {
        manifestSucceeded + folderSucceeded + decoyNoteSucceeded + itemSucceeded
    }

    var totalFailed: Int {
        manifestFailed + folderFailed + decoyNoteFailed + itemFailed
    }

    var totalRecords: Int {
        manifestTotal + folderTotal + decoyNoteTotal + itemTotal
    }

    var isFinished: Bool {
        finishedAt != nil
    }

    var displayText: String {
        "Records \(totalSucceeded)/\(totalRecords) synced, failed \(totalFailed)"
    }

    var statusText: String {
        if totalRecords == 0 {
            return L.string("No items need iCloud backup right now.")
        }
        if totalFailed == 0 {
            return L.string("All encrypted items are backed up to iCloud.")
        }
        return L.format("%d item(s) could not be backed up. Your local vault data is still safe on this device.", totalFailed)
    }

    mutating func finish() {
        finishedAt = Date()
    }

    mutating func addFailure(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        failureMessages.append(message)
        if failureMessages.count > 6 {
            failureMessages.removeFirst(failureMessages.count - 6)
        }
    }
}

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

    var lastSuccessfulSyncText: String {
        switch self {
        case .synced(let date):
            return date.formatted(date: .abbreviated, time: .shortened)
        default:
            return L.string("Never")
        }
    }
}

struct CloudKitChangeSubscriptionDescriptor: Equatable {
    let recordType: String
    let subscriptionID: String
    let sendsSilentPush: Bool
}

struct CloudKitSchemaSeedDescriptor: Equatable {
    let recordType: String
    let recordName: String
}

enum CloudRemoteChangeReason: Equatable {
    case recordType(String)

    var recordType: String {
        switch self {
        case .recordType(let recordType): recordType
        }
    }

    var displayName: String {
        recordType
    }
}

enum CloudChangeSubscriptionStatus: Equatable {
    case notRegistered
    case registering
    case registered(Date)
    case failed(String)

    var title: String {
        switch self {
        case .notRegistered: L.string("Not Registered")
        case .registering: L.string("Registering")
        case .registered: L.string("Active")
        case .failed: L.string("Failed")
        }
    }

    var detail: String {
        switch self {
        case .notRegistered:
            return L.string("CloudKit change notifications have not been registered on this device yet.")
        case .registering:
            return L.string("Registering CloudKit change notifications for this device.")
        case .registered(let date):
            return L.format("CloudKit change notifications registered %@", date.formatted(date: .omitted, time: .shortened))
        case .failed(let message):
            return message
        }
    }
}

enum CloudSchemaIssue: Equatable {
    case missingRecordType
    case missingQueryableIndex
}

struct CloudSchemaReadiness: Equatable {
    var missingRecordTypes: [String] = []
    var missingQueryableIndexes: [String] = []
    var lastSchemaError: String?

    var status: String {
        if missingRecordTypes.isEmpty && missingQueryableIndexes.isEmpty {
            return L.string("Ready")
        }
        return L.string("Needs Dashboard Setup")
    }

    var detail: String {
        if missingRecordTypes.isEmpty && missingQueryableIndexes.isEmpty {
            return L.string("CloudKit schema seed records have been written. Queryable indexes are ready or have not reported an error.")
        }
        return L.string("CloudKit Development schema needs Dashboard setup before full multi-device sync can read every record type.")
    }

    mutating func record(recordType: String, issue: CloudSchemaIssue, detail: String) {
        switch issue {
        case .missingRecordType:
            appendUnique(recordType, to: \.missingRecordTypes)
        case .missingQueryableIndex:
            appendUnique(recordType, to: \.missingQueryableIndexes)
        }
        lastSchemaError = "\(recordType): \(detail)"
    }

    mutating func markSeeded(recordType: String) {
        missingRecordTypes.removeAll { $0 == recordType }
    }

    private mutating func appendUnique(_ value: String, to keyPath: WritableKeyPath<CloudSchemaReadiness, [String]>) {
        guard !self[keyPath: keyPath].contains(value) else { return }
        self[keyPath: keyPath].append(value)
        self[keyPath: keyPath].sort()
    }
}

struct CloudSyncDiagnosticSnapshot: Equatable {
    let containerIdentifier: String
    let environment: String
    let databaseScope: String
    let remoteTriggerMode: String
    let subscriptionStatus: String
    let subscriptionDetail: String
    let subscriptionRecordTypes: [String]
    let subscriptionIDs: [String]
    let iCloudStatus: String
    let lastSuccessfulSync: String
    let lastError: String?
    let lastRemoteChange: String
    let schemaStatus: String
    let schemaDetail: String
    let missingRecordTypes: [String]
    let missingQueryableIndexes: [String]
    let lastSchemaError: String?
}

@MainActor
final class CloudSyncRemoteChangeRouter: ObservableObject {
    static let shared = CloudSyncRemoteChangeRouter()

    @Published var pendingReason: CloudRemoteChangeReason?
    @Published private(set) var lastReason: CloudRemoteChangeReason?
    @Published private(set) var lastReceivedAt: Date?
    @Published private(set) var registrationStatus: String = L.string("Not Registered")

    init() {}

    @discardableResult
    func receive(subscriptionID: String?) -> Bool {
        guard let reason = CloudKitSyncService.remoteChangeReason(subscriptionID: subscriptionID) else {
            return false
        }
        pendingReason = reason
        lastReason = reason
        lastReceivedAt = Date()
        return true
    }

    @discardableResult
    func receive(userInfo: [AnyHashable: Any]) -> Bool {
        guard let reason = CloudKitSyncService.remoteChangeReason(fromRemoteNotificationUserInfo: userInfo) else {
            return false
        }
        pendingReason = reason
        lastReason = reason
        lastReceivedAt = Date()
        return true
    }

    func consume(_ reason: CloudRemoteChangeReason) {
        if pendingReason == reason {
            pendingReason = nil
        }
    }

    func markRemoteNotificationsRegistered() {
        registrationStatus = L.string("Registered")
    }

    func markRemoteNotificationsFailed(_ message: String) {
        registrationStatus = message
    }
}

@MainActor
final class CloudKitSyncService: ObservableObject {
    static let containerIdentifier = "iCloud.app.landlady.www.privacy"
    static let changeSubscriptionDescriptors: [CloudKitChangeSubscriptionDescriptor] = [
        CloudKitChangeSubscriptionDescriptor(recordType: "VaultManifest", subscriptionID: "privacy.vault.change.VaultManifest", sendsSilentPush: true),
        CloudKitChangeSubscriptionDescriptor(recordType: "VaultFolder", subscriptionID: "privacy.vault.change.VaultFolder", sendsSilentPush: true),
        CloudKitChangeSubscriptionDescriptor(recordType: "VaultItem", subscriptionID: "privacy.vault.change.VaultItem", sendsSilentPush: true),
        CloudKitChangeSubscriptionDescriptor(recordType: "DecoyNote", subscriptionID: "privacy.vault.change.DecoyNote", sendsSilentPush: true)
    ]
    static let schemaSeedDescriptors: [CloudKitSchemaSeedDescriptor] = [
        CloudKitSchemaSeedDescriptor(recordType: "VaultFolder", recordName: "__privacy_schema_seed_vault_folder"),
        CloudKitSchemaSeedDescriptor(recordType: "VaultItem", recordName: "__privacy_schema_seed_vault_item"),
        CloudKitSchemaSeedDescriptor(recordType: "DecoyNote", recordName: "__privacy_schema_seed_decoy_note")
    ]

    static var cloudKitEnvironment: String {
        #if DEBUG
        "Development"
        #else
        "Production"
        #endif
    }

    @Published var state: CloudSyncState = .checking
    @Published var lastSyncError: String?
    @Published private(set) var recentLogs: [CloudSyncLogEntry] = []
    @Published private(set) var lastRunSummary: CloudSyncRunSummary?
    @Published private(set) var changeSubscriptionStatus: CloudChangeSubscriptionStatus = .notRegistered
    @Published private(set) var schemaReadiness = CloudSchemaReadiness()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "CloudKitSync")
    private let container = CKContainer(identifier: CloudKitSyncService.containerIdentifier)
    private let containerIdentifier = CloudKitSyncService.containerIdentifier
    private let primaryManifestRecordName = "primary-vault-manifest"
    private let maxRecentLogCount = 100
    private let logFileName = "icloud-sync.log"
    private var database: CKDatabase {
        container.privateCloudDatabase
    }

    var logFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(logFileName)
    }

    var exportableLogText: String {
        readLogFile()
    }

    func readLogFile() -> String {
        (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""
    }

    static func remoteChangeReason(subscriptionID: String?) -> CloudRemoteChangeReason? {
        guard let subscriptionID else { return nil }
        guard let descriptor = changeSubscriptionDescriptors.first(where: { $0.subscriptionID == subscriptionID }) else {
            return nil
        }
        return .recordType(descriptor.recordType)
    }

    static func remoteChangeReason(fromRemoteNotificationUserInfo userInfo: [AnyHashable: Any]) -> CloudRemoteChangeReason? {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return nil
        }
        return remoteChangeReason(subscriptionID: notification.subscriptionID)
    }

    static func isSchemaSeedRecordName(_ recordName: String) -> Bool {
        schemaSeedDescriptors.contains { $0.recordName == recordName }
    }

    static func userRecords(from records: [CKRecord]) -> [CKRecord] {
        records.filter { !isSchemaSeedRecordName($0.recordID.recordName) }
    }

    func recordMissingCloudSchema(recordType: String, issue: CloudSchemaIssue, detail: String) {
        schemaReadiness.record(recordType: recordType, issue: issue, detail: detail)
    }

    func diagnosticSnapshot(lastRemoteChange: CloudRemoteChangeReason?) -> CloudSyncDiagnosticSnapshot {
        CloudSyncDiagnosticSnapshot(
            containerIdentifier: Self.containerIdentifier,
            environment: Self.cloudKitEnvironment,
            databaseScope: "Private Database",
            remoteTriggerMode: "Push + foreground refresh",
            subscriptionStatus: changeSubscriptionStatus.title,
            subscriptionDetail: changeSubscriptionStatus.detail,
            subscriptionRecordTypes: Self.changeSubscriptionDescriptors.map(\.recordType),
            subscriptionIDs: Self.changeSubscriptionDescriptors.map(\.subscriptionID),
            iCloudStatus: state.title,
            lastSuccessfulSync: state.lastSuccessfulSyncText,
            lastError: lastSyncError,
            lastRemoteChange: lastRemoteChange?.displayName ?? L.string("None"),
            schemaStatus: schemaReadiness.status,
            schemaDetail: schemaReadiness.detail,
            missingRecordTypes: schemaReadiness.missingRecordTypes,
            missingQueryableIndexes: schemaReadiness.missingQueryableIndexes,
            lastSchemaError: schemaReadiness.lastSchemaError
        )
    }

    @discardableResult
    func ensureChangeSubscriptions() async -> Bool {
        guard await ensureCloudAvailable() else {
            appendLog("CloudKit change subscriptions skipped: cloud unavailable")
            return false
        }

        await seedCloudKitDevelopmentSchema()

        changeSubscriptionStatus = .registering
        do {
            for descriptor in Self.changeSubscriptionDescriptors {
                let subscription = CKQuerySubscription(
                    recordType: descriptor.recordType,
                    predicate: NSPredicate(value: true),
                    subscriptionID: descriptor.subscriptionID,
                    options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
                )
                let notificationInfo = CKSubscription.NotificationInfo()
                notificationInfo.shouldSendContentAvailable = descriptor.sendsSilentPush
                subscription.notificationInfo = notificationInfo
                _ = try await database.save(subscription)
                appendLog("Registered CloudKit change subscription id=\(descriptor.subscriptionID) recordType=\(descriptor.recordType)")
            }
            let date = Date()
            changeSubscriptionStatus = .registered(date)
            appendLog("CloudKit change subscriptions active count=\(Self.changeSubscriptionDescriptors.count)")
            return true
        } catch {
            let detail = describe(error, context: "CloudKit change subscription registration failed")
            let message = userFacingMessage(for: error, fallback: L.string("CloudKit change notifications could not be registered. Foreground refresh will still sync your devices."))
            changeSubscriptionStatus = .failed(message)
            lastSyncError = message
            appendLog(detail)
            return false
        }
    }

    @discardableResult
    func seedCloudKitDevelopmentSchema() async -> Bool {
        var didSeedAllRecords = true
        let now = Date()

        for descriptor in Self.schemaSeedDescriptors {
            let recordID = CKRecord.ID(recordName: descriptor.recordName)
            do {
                _ = try await saveRecord(recordType: descriptor.recordType, recordID: recordID) { record in
                    assignSchemaSeedFields(to: record, descriptor: descriptor, now: now)
                }
                schemaReadiness.markSeeded(recordType: descriptor.recordType)
                appendLog("Seeded CloudKit schema recordType=\(descriptor.recordType) record=\(descriptor.recordName)")
            } catch {
                didSeedAllRecords = false
                let detail = describe(error, context: "CloudKit schema seed failed recordType=\(descriptor.recordType)")
                schemaReadiness.lastSchemaError = detail
                appendLog(detail)
            }
        }

        return didSeedAllRecords
    }

    private func assignSchemaSeedFields(to record: CKRecord, descriptor: CloudKitSchemaSeedDescriptor, now: Date) {
        record["schemaSeed"] = 1
        record["updatedAt"] = now
        record["deletedAt"] = now
        record["localRevision"] = 0

        switch descriptor.recordType {
        case "VaultFolder":
            record["folderId"] = descriptor.recordName
            record["encryptedName"] = Data("schema-seed-folder".utf8)
            record["sortOrder"] = -1
        case "VaultItem":
            record["itemId"] = descriptor.recordName
            record["type"] = VaultItemKind.other.rawValue
            record["encryptedMetadata"] = Data("schema-seed-item".utf8)
            record["encryptedFileKey"] = Data("schema-seed-key".utf8)
            record["byteSize"] = Int64(0)
            record["folderId"] = "__privacy_schema_seed_vault_folder"
            record["favorite"] = 0
            record["createdAt"] = now
            record["assetState"] = VaultAssetState.cloudOnly.rawValue
            record["importFingerprint"] = descriptor.recordName
        case "DecoyNote":
            record["noteId"] = descriptor.recordName
            record["encryptedPayload"] = Data("schema-seed-decoy-note".utf8)
            record["isPinned"] = 0
            record["sortOrder"] = -1.0
            record["createdAt"] = now
        default:
            break
        }
    }

    func clearLogs() {
        recentLogs.removeAll()
        lastRunSummary = nil
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    func checkAccountStatus() async {
        appendLog("Checking iCloud account status for \(containerIdentifier)")
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                state = .available
                lastSyncError = nil
                appendLog("iCloud account available")
            case .noAccount:
                state = .unavailable(L.string("Not signed into iCloud. Items remain encrypted locally."))
                lastSyncError = state.detail
                appendLog("iCloud account unavailable: noAccount")
            case .restricted:
                state = .unavailable(L.string("This iCloud account is restricted."))
                lastSyncError = state.detail
                appendLog("iCloud account unavailable: restricted")
            case .couldNotDetermine:
                state = .unavailable(L.string("Unable to verify iCloud status."))
                lastSyncError = state.detail
                appendLog("iCloud account unavailable: couldNotDetermine")
            case .temporarilyUnavailable:
                state = .unavailable(L.string("iCloud is temporarily unavailable."))
                lastSyncError = state.detail
                appendLog("iCloud account unavailable: temporarilyUnavailable")
            @unknown default:
                state = .unavailable(L.string("Unknown iCloud status."))
                lastSyncError = state.detail
                appendLog("iCloud account unavailable: unknown")
            }
        } catch {
            let detail = describe(error, context: "iCloud account status failed")
            let message = userFacingMessage(for: error, fallback: L.string("Unable to verify iCloud status."))
            state = .failed(message)
            lastSyncError = message
            appendLog(detail)
        }
    }

    func runWritableProbe() async -> Bool {
        guard await ensureCloudAvailable() else {
            appendLog("CloudKit writable probe skipped: cloud unavailable")
            return false
        }

        state = .syncing
        let recordID = CKRecord.ID(recordName: "probe-\(UUID().uuidString)")
        let record = CKRecord(recordType: "SyncDiagnosticProbe", recordID: recordID)
        record["createdAt"] = Date()
        record["containerIdentifier"] = containerIdentifier
        record["appVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        do {
            _ = try await database.save(record)
            _ = try? await database.deleteRecord(withID: recordID)
            state = .synced(Date())
            lastSyncError = nil
            appendLog("CloudKit writable probe succeeded record=\(recordID.recordName)")
            return true
        } catch {
            let detail = describe(error, context: "CloudKit writable probe failed")
            let message = userFacingMessage(for: error, fallback: L.string("Unable to write to iCloud. Your data remains saved locally."))
            state = .failed(message)
            lastSyncError = message
            appendLog(detail)
            return false
        }
    }

    func beginSyncRun(itemCount: Int, folderCount: Int, decoyNoteCount: Int, manifestCount: Int) {
        lastRunSummary = CloudSyncRunSummary(
            manifestTotal: manifestCount,
            folderTotal: folderCount,
            decoyNoteTotal: decoyNoteCount,
            itemTotal: itemCount
        )
        appendLog("Manual iCloud backup started container=\(containerIdentifier) manifests=\(manifestCount) folders=\(folderCount) decoyNotes=\(decoyNoteCount) items=\(itemCount)")
    }

    func recordManifestSync(success: Bool, failure: String?) {
        if success {
            lastRunSummary?.manifestSucceeded += 1
        } else {
            lastRunSummary?.manifestFailed += 1
            lastRunSummary?.addFailure(failure)
        }
    }

    func recordFolderSync(success: Bool, failure: String?) {
        if success {
            lastRunSummary?.folderSucceeded += 1
        } else {
            lastRunSummary?.folderFailed += 1
            lastRunSummary?.addFailure(failure)
        }
    }

    func recordDecoyNoteSync(success: Bool, failure: String?) {
        if success {
            lastRunSummary?.decoyNoteSucceeded += 1
        } else {
            lastRunSummary?.decoyNoteFailed += 1
            lastRunSummary?.addFailure(failure)
        }
    }

    func recordItemSync(success: Bool, failure: String?) {
        if success {
            lastRunSummary?.itemSucceeded += 1
        } else {
            lastRunSummary?.itemFailed += 1
            lastRunSummary?.addFailure(failure)
        }
    }

    func finishSyncRun() {
        lastRunSummary?.finish()
        if let summary = lastRunSummary {
            appendLog("Manual iCloud backup finished \(summary.displayText)")
        }
    }

    func syncManifest(_ manifest: VaultManifest) async -> Bool {
        guard await ensureCloudAvailable() else {
            manifest.syncStatus = .pending
            appendLog("Skipped VaultManifest sync: cloud unavailable")
            return false
        }
        state = .syncing
        let recordID = CKRecord.ID(recordName: primaryManifestRecordName)

        do {
            appendLog("Saving VaultManifest id=\(manifest.id) record=\(recordID.recordName) packageBytes=\(manifest.encryptedRootKeyPackage.count) nameBytes=\(manifest.encryptedVaultName.count)")
            _ = try await saveRecord(recordType: "VaultManifest", recordID: recordID) { record in
                record["vaultId"] = manifest.id
                record["schemaVersion"] = manifest.schemaVersion
                record["encryptedVaultName"] = manifest.encryptedVaultName
                record["encryptedRootKeyPackage"] = manifest.encryptedRootKeyPackage
                record["updatedAt"] = manifest.updatedAt
            }
            manifest.syncStatus = .synced
            state = .synced(Date())
            lastSyncError = nil
            appendLog("Synced VaultManifest id=\(manifest.id) record=\(recordID.recordName)")
            return true
        } catch {
            manifest.syncStatus = .failed
            let detail = describe(error, context: "VaultManifest sync failed id=\(manifest.id)")
            let message = userFacingMessage(for: error, fallback: L.string("iCloud backup failed. Your data remains saved locally."))
            state = .failed(message)
            lastSyncError = message
            appendLog(detail)
            return false
        }
    }

    func fetchRemoteManifest() async -> CKRecord? {
        guard await ensureCloudAvailable() else { return nil }

        state = .syncing
        let primaryID = CKRecord.ID(recordName: primaryManifestRecordName)
        do {
            let primary = try await database.record(for: primaryID)
            state = .synced(Date())
            lastSyncError = nil
            appendLog("Fetched primary VaultManifest record=\(primaryID.recordName)")
            return primary
        } catch {
            if !isUnknownItem(error) {
                appendLog(describe(error, context: "Primary VaultManifest fetch failed record=\(primaryID.recordName)"))
            } else {
                appendLog("Primary VaultManifest not found record=\(primaryID.recordName); checking legacy manifest records")
            }
        }

        let records = await fetchRecords(recordType: "VaultManifest")
        let latest = records.max {
            ($0["updatedAt"] as? Date ?? .distantPast) < ($1["updatedAt"] as? Date ?? .distantPast)
        }
        state = .synced(Date())
        lastSyncError = nil
        if let latest {
            appendLog("Fetched legacy VaultManifest record=\(latest.recordID.recordName)")
        } else {
            appendLog("No remote VaultManifest found")
        }
        return latest
    }

    func syncItem(_ item: VaultItem) async -> Bool {
        guard await ensureCloudAvailable() else {
            item.syncStatus = .pending
            item.lastSyncError = lastSyncError ?? L.string("iCloud is not available.")
            appendLog("Skipped VaultItem sync id=\(item.id): \(item.lastSyncError ?? "cloud unavailable")")
            return false
        }

        state = .syncing
        let fileURL = VaultFileStore.assetURL(for: item.encryptedFilePath)
        let requiresFileAsset = item.kind != .link && item.deletedAt == nil
        appendLog("Syncing VaultItem id=\(item.id) kind=\(item.kind.rawValue) bytes=\(item.byteSize) requiresFileAsset=\(requiresFileAsset) file=\(VaultFileStore.encryptedFileAttributesForLog(path: item.encryptedFilePath)) thumb=\(VaultFileStore.encryptedFileAttributesForLog(path: item.encryptedThumbPath))")
        guard !requiresFileAsset || VaultFileStore.fileExists(path: item.encryptedFilePath) else {
            return failItemSync(item, reason: L.string("Local encrypted file is missing; cannot upload to iCloud."))
        }

        let recordID = CKRecord.ID(recordName: item.cloudRecordName ?? item.id)
        var fileAsset: CKAsset?
        var thumbAsset: CKAsset?

        if requiresFileAsset {
            do {
                try VaultFileStore.prepareForCloudAssetUpload(path: item.encryptedFilePath)
            } catch {
                return failItemSync(item, reason: describe(error, context: "Preparing encrypted file for iCloud failed id=\(item.id)"))
            }
            fileAsset = CKAsset(fileURL: fileURL)
        }
        if let thumbPath = item.encryptedThumbPath, VaultFileStore.fileExists(path: thumbPath) {
            do {
                try VaultFileStore.prepareForCloudAssetUpload(path: thumbPath)
            } catch {
                appendLog(describe(error, context: "Preparing thumbnail for iCloud failed id=\(item.id)"))
            }
            thumbAsset = CKAsset(fileURL: VaultFileStore.assetURL(for: thumbPath))
        }

        do {
            appendLog("Saving VaultItem record=\(recordID.recordName) type=\(item.kind.rawValue) hasFileAsset=\(fileAsset != nil) hasThumbAsset=\(thumbAsset != nil)")
            let saved = try await saveRecord(recordType: "VaultItem", recordID: recordID) { record in
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
                if item.deletedAt != nil {
                    record["fileAsset"] = nil
                    record["thumbAsset"] = nil
                } else if let fileAsset {
                    record["fileAsset"] = fileAsset
                }
                if item.deletedAt == nil, let thumbAsset {
                    record["thumbAsset"] = thumbAsset
                }
            }
            item.cloudRecordName = saved.recordID.recordName
            item.syncStatus = .synced
            item.lastSyncError = nil
            state = .synced(Date())
            lastSyncError = nil
            appendLog("Synced VaultItem id=\(item.id) record=\(saved.recordID.recordName)")
            return true
        } catch {
            item.syncStatus = .failed
            let detail = describe(error, context: "VaultItem sync failed id=\(item.id) kind=\(item.kind.rawValue)")
            let message = userFacingMessage(for: error, fallback: L.string("This item could not be backed up to iCloud. It remains saved locally."))
            item.lastSyncError = message
            state = .failed(message)
            lastSyncError = message
            appendLog(detail)
            return false
        }
    }

    func fetchRemoteItems() async -> [CKRecord] {
        guard await ensureCloudAvailable() else { return [] }

        state = .syncing
        let records = Self.userRecords(from: await fetchRecords(recordType: "VaultItem"))
        state = .synced(Date())
        lastSyncError = nil
        return records
    }

    func fetchRemoteFolders() async -> [CKRecord] {
        guard await ensureCloudAvailable() else { return [] }

        state = .syncing
        let records = Self.userRecords(from: await fetchRecords(recordType: "VaultFolder"))
        state = .synced(Date())
        lastSyncError = nil
        return records
    }

    func syncDecoyNote(_ note: DecoyNoteRecord) async -> Bool {
        guard await ensureCloudAvailable() else {
            note.syncStatus = .pending
            note.lastSyncError = lastSyncError ?? L.string("iCloud is not available.")
            appendLog("Skipped DecoyNote sync id=\(note.id): \(note.lastSyncError ?? "cloud unavailable")")
            return false
        }

        state = .syncing
        let recordID = CKRecord.ID(recordName: note.cloudRecordName ?? note.id)

        do {
            appendLog("Saving DecoyNote id=\(note.id) payloadBytes=\(note.encryptedPayload.count)")
            let saved = try await saveRecord(recordType: "DecoyNote", recordID: recordID) { record in
                record["noteId"] = note.id
                record["encryptedPayload"] = note.encryptedPayload
                record["isPinned"] = note.isPinned ? 1 : 0
                record["sortOrder"] = note.sortOrder
                record["createdAt"] = note.createdAt
                record["updatedAt"] = note.updatedAt
                record["deletedAt"] = note.deletedAt
                record["localRevision"] = note.localRevision
            }
            note.cloudRecordName = saved.recordID.recordName
            note.syncStatus = .synced
            note.lastSyncError = nil
            state = .synced(Date())
            lastSyncError = nil
            appendLog("Synced DecoyNote id=\(note.id)")
            return true
        } catch {
            note.syncStatus = .failed
            let detail = describe(error, context: "DecoyNote sync failed id=\(note.id)")
            let message = userFacingMessage(for: error, fallback: L.string("iCloud backup failed. Your data remains saved locally."))
            note.lastSyncError = message
            state = .failed(message)
            lastSyncError = message
            appendLog(detail)
            return false
        }
    }

    func fetchRemoteDecoyNotes() async -> [CKRecord] {
        guard await ensureCloudAvailable() else { return [] }

        state = .syncing
        let records = Self.userRecords(from: await fetchRecords(recordType: "DecoyNote"))
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
            appendLog("Downloaded assets for VaultItem id=\(item.id) file=\(fileURL != nil) thumb=\(thumbURL != nil)")
            return (fileURL, thumbURL)
        } catch {
            item.assetState = .failed
            let detail = describe(error, context: "VaultItem asset download failed id=\(item.id)")
            let message = userFacingMessage(for: error, fallback: L.string("Unable to download this item from iCloud."))
            item.lastDownloadError = message
            state = .failed(message)
            lastSyncError = message
            appendLog(detail)
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
            appendLog("Skipped VaultFolder sync id=\(folder.id): cloud unavailable")
            return false
        }

        state = .syncing
        let recordID = CKRecord.ID(recordName: folder.cloudRecordName ?? folder.id)

        do {
            appendLog("Saving VaultFolder id=\(folder.id) nameBytes=\(folder.encryptedName.count)")
            let saved = try await saveRecord(recordType: "VaultFolder", recordID: recordID) { record in
                record["folderId"] = folder.id
                record["encryptedName"] = folder.encryptedName
                record["sortOrder"] = folder.sortOrder
                record["updatedAt"] = folder.updatedAt
                record["deletedAt"] = folder.deletedAt
                record["localRevision"] = folder.localRevision
            }
            folder.cloudRecordName = saved.recordID.recordName
            folder.syncStatus = .synced
            state = .synced(Date())
            lastSyncError = nil
            appendLog("Synced VaultFolder id=\(folder.id)")
            return true
        } catch {
            folder.syncStatus = .failed
            let detail = describe(error, context: "VaultFolder sync failed id=\(folder.id)")
            let message = userFacingMessage(for: error, fallback: L.string("iCloud backup failed. Your data remains saved locally."))
            state = .failed(message)
            lastSyncError = message
            appendLog(detail)
            return false
        }
    }

    private func existingRecord(recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch {
            if isUnknownItem(error) {
                return nil
            }
            throw error
        }
    }

    private func saveRecord(recordType: String, recordID: CKRecord.ID, assign: (CKRecord) -> Void) async throws -> CKRecord {
        let record = try await existingRecord(recordID: recordID) ?? CKRecord(recordType: recordType, recordID: recordID)
        assign(record)
        return try await database.save(record)
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
        item.lastSyncError = reason
        state = .failed(reason)
        lastSyncError = reason
        appendLog("VaultItem sync failed id=\(item.id): \(reason)")
        return false
    }

    private func fetchRecords(recordType: String) async -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let (records, cursor) = await fetchRecords(query: query, recordType: recordType)
        guard let cursor else { return records }
        return await fetchRemainingRecords(cursor: cursor, recordType: recordType, accumulated: records)
    }

    private func fetchRecords(query: CKQuery, recordType: String) async -> ([CKRecord], CKQueryOperation.Cursor?) {
        await withCheckedContinuation { continuation in
            let operation = CKQueryOperation(query: query)
            configure(operation: operation, recordType: recordType, continuation: continuation)
            database.add(operation)
        }
    }

    private func fetchRecords(cursor: CKQueryOperation.Cursor, recordType: String) async -> ([CKRecord], CKQueryOperation.Cursor?) {
        await withCheckedContinuation { continuation in
            let operation = CKQueryOperation(cursor: cursor)
            configure(operation: operation, recordType: recordType, continuation: continuation)
            database.add(operation)
        }
    }

    private func fetchRemainingRecords(cursor: CKQueryOperation.Cursor, recordType: String, accumulated: [CKRecord]) async -> [CKRecord] {
        let (records, nextCursor) = await fetchRecords(cursor: cursor, recordType: recordType)
        let combined = accumulated + records
        guard let nextCursor else { return combined }
        return await fetchRemainingRecords(cursor: nextCursor, recordType: recordType, accumulated: combined)
    }

    private func configure(
        operation: CKQueryOperation,
        recordType: String,
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
                    let detail = self.describe(error, context: "CloudKit query failed recordType=\(recordType)")
                    if self.isMissingRecordType(error) {
                        self.recordMissingCloudSchema(recordType: recordType, issue: .missingRecordType, detail: detail)
                        self.appendLog("CloudKit record type \(recordType) is not created yet; treating remote \(recordType) list as empty | \(detail)")
                        return
                    }
                    if self.isMissingQueryableIndex(error) {
                        self.recordMissingCloudSchema(recordType: recordType, issue: .missingQueryableIndex, detail: detail)
                        self.appendLog("CloudKit query for \(recordType) needs a queryable index; treating remote \(recordType) list as empty until schema is indexed | \(detail)")
                        return
                    }
                    let message = self.userFacingMessage(for: error, fallback: L.string("Unable to read from iCloud."))
                    self.state = .failed(message)
                    self.lastSyncError = message
                    self.appendLog(detail)
                }
                continuation.resume(returning: (records, nil))
            }
        }
    }

    private func isUnknownItem(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    private func isMissingRecordType(_ error: Error) -> Bool {
        if isUnknownItem(error) {
            return true
        }
        return cloudKitErrorText(error).contains("Did not find record type")
    }

    private func isMissingQueryableIndex(_ error: Error) -> Bool {
        if (error as? CKError)?.code == .invalidArguments {
            return true
        }
        return cloudKitErrorText(error).contains("not marked queryable")
    }

    private func cloudKitErrorText(_ error: Error) -> String {
        let nsError = error as NSError
        let userInfoText = nsError.userInfo.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
        return [error.localizedDescription, userInfoText].joined(separator: " ")
    }

    func appendLog(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let entry = CloudSyncLogEntry(date: Date(), message: message)
        recentLogs.insert(entry, at: 0)
        if recentLogs.count > maxRecentLogCount {
            recentLogs.removeLast(recentLogs.count - maxRecentLogCount)
        }
        appendLogFile(entry.displayText)
    }

    private func appendLogFile(_ line: String) {
        let lineData = Data((line + "\n").utf8)
        let url = logFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: lineData)
            }
        } else {
            try? lineData.write(to: url, options: [.atomic])
        }
    }

    private func userFacingMessage(for error: Error, fallback: String) -> String {
        guard let ckError = error as? CKError else { return fallback }
        switch ckError.code {
        case .quotaExceeded:
            return L.string("Your iCloud storage is full. This item could not be backed up to iCloud, but it remains saved locally on this device.")
        case .notAuthenticated:
            return L.string("Sign in to iCloud to back up encrypted vault data. Your data remains saved locally.")
        case .networkUnavailable, .networkFailure:
            return L.string("Network is unavailable. iCloud backup will stay pending and your data remains saved locally.")
        case .missingEntitlement, .badContainer:
            return L.string("iCloud backup is not configured correctly for this app. Your data remains saved locally.")
        case .invalidArguments:
            return L.string("iCloud backup schema needs to be updated before this data can sync.")
        case .unknownItem:
            return L.string("No iCloud backup data was found for this section yet.")
        case .serviceUnavailable, .requestRateLimited, .accountTemporarilyUnavailable:
            return L.string("iCloud is temporarily unavailable. Please try again later. Your data remains saved locally.")
        default:
            return fallback
        }
    }

    private func describe(_ error: Error, context: String) -> String {
        var parts: [String] = [context, error.localizedDescription]
        let nsError = error as NSError
        parts.append("domain=\(nsError.domain)")
        parts.append("code=\(nsError.code)")

        if let ckError = error as? CKError {
            parts.append("ckCode=\(cloudKitCodeName(ckError.code))")
            if let retryAfter = ckError.retryAfterSeconds {
                parts.append("retryAfter=\(retryAfter)s")
            }
            if let partialErrors = ckError.partialErrorsByItemID, !partialErrors.isEmpty {
                let partials = partialErrors.map { key, value in
                    let keyDescription: String
                    if let recordID = key as? CKRecord.ID {
                        keyDescription = recordID.recordName
                    } else {
                        keyDescription = String(describing: key)
                    }
                    return "\(keyDescription):\((value as NSError).domain)#\((value as NSError).code)"
                }
                parts.append("partialErrors=\(partials.joined(separator: ","))")
            }
        }

        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
            parts.append("reason=\(reason)")
        }
        if let suggestion = nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String, !suggestion.isEmpty {
            parts.append("suggestion=\(suggestion)")
        }
        if let serverDescription = nsError.userInfo["CKErrorDescription"] as? String, !serverDescription.isEmpty {
            parts.append("server=\(serverDescription)")
        }
        let userInfoDescription = nsError.userInfo
            .filter { key, _ in
                let keyString = String(describing: key)
                return keyString != NSLocalizedDescriptionKey
                    && keyString != NSLocalizedFailureReasonErrorKey
                    && keyString != NSLocalizedRecoverySuggestionErrorKey
                    && keyString != "CKErrorDescription"
            }
            .map { key, value in "\(key)=\(value)" }
            .sorted()
            .joined(separator: ";")
        if !userInfoDescription.isEmpty {
            parts.append("userInfo=\(userInfoDescription)")
        }
        return parts.joined(separator: " | ")
    }

    private func cloudKitCodeName(_ code: CKError.Code) -> String {
        switch code {
        case .internalError: "internalError"
        case .partialFailure: "partialFailure"
        case .networkUnavailable: "networkUnavailable"
        case .networkFailure: "networkFailure"
        case .badContainer: "badContainer"
        case .serviceUnavailable: "serviceUnavailable"
        case .requestRateLimited: "requestRateLimited"
        case .missingEntitlement: "missingEntitlement"
        case .notAuthenticated: "notAuthenticated"
        case .permissionFailure: "permissionFailure"
        case .unknownItem: "unknownItem"
        case .invalidArguments: "invalidArguments"
        case .resultsTruncated: "resultsTruncated"
        case .serverRecordChanged: "serverRecordChanged"
        case .serverRejectedRequest: "serverRejectedRequest"
        case .assetFileNotFound: "assetFileNotFound"
        case .assetFileModified: "assetFileModified"
        case .incompatibleVersion: "incompatibleVersion"
        case .constraintViolation: "constraintViolation"
        case .operationCancelled: "operationCancelled"
        case .changeTokenExpired: "changeTokenExpired"
        case .batchRequestFailed: "batchRequestFailed"
        case .zoneBusy: "zoneBusy"
        case .badDatabase: "badDatabase"
        case .quotaExceeded: "quotaExceeded"
        case .zoneNotFound: "zoneNotFound"
        case .limitExceeded: "limitExceeded"
        case .userDeletedZone: "userDeletedZone"
        case .tooManyParticipants: "tooManyParticipants"
        case .alreadyShared: "alreadyShared"
        case .referenceViolation: "referenceViolation"
        case .managedAccountRestricted: "managedAccountRestricted"
        case .accountTemporarilyUnavailable: "accountTemporarilyUnavailable"
        case .participantMayNeedVerification: "participantMayNeedVerification"
        case .participantAlreadyInvited: "participantAlreadyInvited"
        case .serverResponseLost: "serverResponseLost"
        case .assetNotAvailable: "assetNotAvailable"
        default: "unknown(\(code.rawValue))"
        }
    }
}
