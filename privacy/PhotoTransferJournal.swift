import CryptoKit
import Foundation

struct PhotoTransferEntry: Codable, Identifiable, Equatable {
    enum State: String, Codable {
        case pending, failed, verified, duplicate, deletionRequested, removed, kept, savedKeepingOriginal
    }
    var id: String // PhotoKit local identifier, never inferred from a filename.
    var vaultID = UUID().uuidString
    var state: State = .pending
    var fingerprint: String?
    var sourceModifiedAt: Date?
    var error: String?

    var needsImport: Bool { state == .pending || state == .failed }
    var canReviewDeletion: Bool { state == .verified || state == .deletionRequested }
}

struct PhotoTransferJournal: Codable, Equatable {
    var id = UUID()
    var folderID: String?
    var entries: [PhotoTransferEntry]
    var cloudBackupRequested: Bool
    var cloudBackupFinished = false
    var createdAt = Date()

    init(assetIDs: [String], folderID: String?, cloudBackupRequested: Bool) {
        var seen = Set<String>()
        entries = assetIDs.filter { seen.insert($0).inserted }.map { PhotoTransferEntry(id: $0) }
        self.folderID = folderID
        self.cloudBackupRequested = cloudBackupRequested
    }
    var savedCount: Int {
        entries.filter { [.verified, .deletionRequested, .removed, .kept, .savedKeepingOriginal].contains($0.state) }.count
    }
    var remainingCount: Int { entries.filter(\.needsImport).count }
    var deletionCount: Int { entries.filter(\.canReviewDeletion).count }
    var removedCount: Int { entries.filter { $0.state == .removed }.count }
}

struct PhotoTransferJournalStore {
    var url: URL = VaultFileStore.vaultDirectory.appendingPathComponent("photo-transfer.enc")

    func load(key: SymmetricKey) throws -> PhotoTransferJournal? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let encrypted = try Data(contentsOf: url)
        return try JSONDecoder().decode(PhotoTransferJournal.self, from: VaultCryptoService.decrypt(encrypted, using: key))
    }
    func save(_ journal: PhotoTransferJournal, key: SymmetricKey) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encrypted = try VaultCryptoService.encrypt(JSONEncoder().encode(journal), using: key)
        try encrypted.write(to: url, options: VaultFileStore.encryptedDataWritingOptions)
    }
    func remove() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

enum PhotoTransferSafety {
    static func canDelete(entry: PhotoTransferEntry, storedFingerprint: String?, sourceFingerprint: String?, localExists: Bool, itemDeleted: Bool) -> Bool {
        entry.canReviewDeletion && localExists && !itemDeleted && entry.fingerprint != nil
            && entry.fingerprint == storedFingerprint && entry.fingerprint == sourceFingerprint
    }

    /// At most the current payload is in memory; one subsequent asset is staged on disk.
    static let prefetchCount = 1
}
