import Foundation
import SwiftData

enum VaultItemKind: String, Codable, CaseIterable {
    case image
    case livePhoto
    case video
    case audio
    case document
    case archive
    case link
    case other
}

enum VaultAssetState: String, Codable, CaseIterable {
    case local
    case cloudOnly
    case downloading
    case failed
}

enum VaultSyncStatus: String, Codable, CaseIterable {
    case local
    case pending
    case synced
    case failed
    case conflict
}

enum SecurityEventKind: String, Codable, CaseIterable {
    case unlocked
    case authFailed
    case backgroundLocked
    case screenshot
    case screenCaptured
    case decoyOpened
    case browserDataCleared
    case cloudKitSynced
}

struct VaultMetadata: Codable {
    var originalName: String
    var mimeType: String
    var source: String
    var note: String
    var importedAt: Date
    var remoteURL: String? = nil
    var originalExtension: String? = nil
}

struct LivePhotoPackage: Codable {
    var stillData: Data
    var pairedVideoData: Data
    var stillFilename: String
    var pairedVideoFilename: String
}

struct DecoyTodoPayload: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var text: String
    var done: Bool
}

struct DecoyNotePayload: Codable, Equatable {
    var title: String
    var body: String
    var folder: String
    var todos: [DecoyTodoPayload]
}

@Model
final class VaultItem {
    var id: String = UUID().uuidString
    var kindRawValue: String = VaultItemKind.other.rawValue
    var encryptedFilePath: String = ""
    var encryptedThumbPath: String?
    @Attribute(.externalStorage) var encryptedMetadata: Data = Data()
    @Attribute(.externalStorage) var encryptedFileKey: Data = Data()
    var byteSize: Int64 = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var folderId: String?
    var isFavorite: Bool = false
    var syncStatusRawValue: String = VaultSyncStatus.pending.rawValue
    var assetStateRawValue: String = VaultAssetState.local.rawValue
    var cloudRecordName: String?
    var localRevision: Int = 1
    var lastSyncError: String?
    var lastDownloadError: String?
    var downloadedAt: Date?
    var importFingerprint: String?

    var kind: VaultItemKind {
        get { VaultItemKind(rawValue: kindRawValue) ?? .other }
        set { kindRawValue = newValue.rawValue }
    }

    var syncStatus: VaultSyncStatus {
        get { VaultSyncStatus(rawValue: syncStatusRawValue) ?? .local }
        set { syncStatusRawValue = newValue.rawValue }
    }

    var assetState: VaultAssetState {
        get { VaultAssetState(rawValue: assetStateRawValue) ?? .local }
        set { assetStateRawValue = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        kind: VaultItemKind,
        encryptedFilePath: String = "",
        encryptedThumbPath: String? = nil,
        encryptedMetadata: Data,
        encryptedFileKey: Data = Data(),
        byteSize: Int64,
        folderId: String? = nil,
        assetState: VaultAssetState = .local,
        cloudRecordName: String? = nil,
        importFingerprint: String? = nil
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.encryptedFilePath = encryptedFilePath
        self.encryptedThumbPath = encryptedThumbPath
        self.encryptedMetadata = encryptedMetadata
        self.encryptedFileKey = encryptedFileKey
        self.byteSize = byteSize
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.folderId = folderId
        self.isFavorite = false
        self.syncStatusRawValue = VaultSyncStatus.pending.rawValue
        self.assetStateRawValue = assetState.rawValue
        self.cloudRecordName = cloudRecordName
        self.localRevision = 1
        self.lastSyncError = nil
        self.lastDownloadError = nil
        self.downloadedAt = assetState == .local ? Date() : nil
        self.importFingerprint = importFingerprint
    }
}

@Model
final class VaultFolder {
    var id: String = UUID().uuidString
    @Attribute(.externalStorage) var encryptedName: Data = Data()
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var syncStatusRawValue: String = VaultSyncStatus.pending.rawValue
    var cloudRecordName: String?
    var localRevision: Int = 1

    var syncStatus: VaultSyncStatus {
        get { VaultSyncStatus(rawValue: syncStatusRawValue) ?? .pending }
        set { syncStatusRawValue = newValue.rawValue }
    }

    init(id: String = UUID().uuidString, encryptedName: Data, sortOrder: Int = 0) {
        self.id = id
        self.encryptedName = encryptedName
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncStatusRawValue = VaultSyncStatus.pending.rawValue
        self.cloudRecordName = nil
        self.localRevision = 1
    }
}

@Model
final class VaultTag {
    var id: String = UUID().uuidString
    @Attribute(.externalStorage) var encryptedName: Data = Data()
    var createdAt: Date = Date()

    init(id: String = UUID().uuidString, encryptedName: Data) {
        self.id = id
        self.encryptedName = encryptedName
        self.createdAt = Date()
    }
}

@Model
final class DecoyNoteRecord {
    var id: String = UUID().uuidString
    @Attribute(.externalStorage) var encryptedPayload: Data = Data()
    var isPinned: Bool = false
    var sortOrder: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var syncStatusRawValue: String = VaultSyncStatus.pending.rawValue
    var cloudRecordName: String?
    var localRevision: Int = 1
    var lastSyncError: String?

    var syncStatus: VaultSyncStatus {
        get { VaultSyncStatus(rawValue: syncStatusRawValue) ?? .pending }
        set { syncStatusRawValue = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        encryptedPayload: Data,
        isPinned: Bool = false,
        sortOrder: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.encryptedPayload = encryptedPayload
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deletedAt = nil
        self.syncStatusRawValue = VaultSyncStatus.pending.rawValue
        self.cloudRecordName = nil
        self.localRevision = 1
        self.lastSyncError = nil
    }
}

@Model
final class SecurityEvent {
    var id: String = UUID().uuidString
    var kindRawValue: String = SecurityEventKind.unlocked.rawValue
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var encryptedPayload: Data?
    var snapshotPath: String?

    var kind: SecurityEventKind {
        get { SecurityEventKind(rawValue: kindRawValue) ?? .unlocked }
        set { kindRawValue = newValue.rawValue }
    }

    init(id: String = UUID().uuidString, kind: SecurityEventKind, encryptedPayload: Data? = nil, snapshotPath: String? = nil) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.createdAt = Date()
        self.encryptedPayload = encryptedPayload
        self.snapshotPath = snapshotPath
    }
}

@Model
final class SubscriptionState {
    var id: String = "subscription"
    var productId: String?
    var isActive: Bool = false
    var expirationDate: Date?
    var lastVerifiedAt: Date = Date()

    init(id: String = "subscription", productId: String? = nil, isActive: Bool = false, expirationDate: Date? = nil) {
        self.id = id
        self.productId = productId
        self.isActive = isActive
        self.expirationDate = expirationDate
        self.lastVerifiedAt = Date()
    }
}

@Model
final class VaultManifest {
    var id: String = UUID().uuidString
    var schemaVersion: Int = 1
    @Attribute(.externalStorage) var encryptedVaultName: Data = Data()
    @Attribute(.externalStorage) var encryptedRootKeyPackage: Data = Data()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var syncStatusRawValue: String = VaultSyncStatus.pending.rawValue

    var syncStatus: VaultSyncStatus {
        get { VaultSyncStatus(rawValue: syncStatusRawValue) ?? .pending }
        set { syncStatusRawValue = newValue.rawValue }
    }

    init(id: String, encryptedVaultName: Data, encryptedRootKeyPackage: Data) {
        self.id = id
        self.schemaVersion = 1
        self.encryptedVaultName = encryptedVaultName
        self.encryptedRootKeyPackage = encryptedRootKeyPackage
        self.createdAt = Date()
        self.updatedAt = Date()
        self.syncStatusRawValue = VaultSyncStatus.pending.rawValue
    }
}
