import Foundation
import OSLog

enum VaultFileStore {
    private nonisolated static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "VaultFileStore")
    nonisolated static let encryptedFileProtection: FileProtectionType = .completeUntilFirstUserAuthentication
    nonisolated static let encryptedDataWritingOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUntilFirstUserAuthentication
    ]

    nonisolated static var vaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Vault", isDirectory: true)
    }

    nonisolated static var objectsDirectory: URL {
        vaultDirectory.appendingPathComponent("objects", isDirectory: true)
    }

    nonisolated static var thumbsDirectory: URL {
        vaultDirectory.appendingPathComponent("thumbs", isDirectory: true)
    }

    nonisolated static var tempDirectory: URL {
        vaultDirectory.appendingPathComponent("temp", isDirectory: true)
    }

    nonisolated static func prepareDirectories() throws {
        try [vaultDirectory, objectsDirectory, thumbsDirectory, tempDirectory].forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    nonisolated static func writeEncryptedObject(_ data: Data, itemId: String) throws -> String {
        try prepareDirectories()
        let url = objectsDirectory.appendingPathComponent("\(itemId).enc")
        try data.write(to: url, options: encryptedDataWritingOptions)
        try setEncryptedFileProtection(at: url)
        logger.debug("Wrote encrypted object for item \(itemId, privacy: .public)")
        return relativePath(for: url)
    }

    static func writeEncryptedThumb(_ data: Data, itemId: String) throws -> String {
        try prepareDirectories()
        let url = thumbsDirectory.appendingPathComponent("\(itemId).thumb.enc")
        try data.write(to: url, options: encryptedDataWritingOptions)
        try setEncryptedFileProtection(at: url)
        logger.debug("Wrote encrypted thumbnail for item \(itemId, privacy: .public)")
        return relativePath(for: url)
    }

    static func copyEncryptedObject(from sourceURL: URL, itemId: String) throws -> String {
        try prepareDirectories()
        let destination = objectsDirectory.appendingPathComponent("\(itemId).enc")
        replaceItem(at: destination, with: sourceURL)
        logger.debug("Copied encrypted object for item \(itemId, privacy: .public)")
        return relativePath(for: destination)
    }

    static func copyEncryptedThumb(from sourceURL: URL, itemId: String) throws -> String {
        try prepareDirectories()
        let destination = thumbsDirectory.appendingPathComponent("\(itemId).thumb.enc")
        replaceItem(at: destination, with: sourceURL)
        logger.debug("Copied encrypted thumbnail for item \(itemId, privacy: .public)")
        return relativePath(for: destination)
    }

    nonisolated static func read(path: String) throws -> Data {
        let url = resolvedURL(for: path)
        do {
            return try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read vault file at \(storedPathForLog(path), privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    static func fileExists(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: resolvedURL(for: path).path)
    }

    static func fileSize(path: String?) -> Int64 {
        guard let path, !path.isEmpty else { return 0 }
        let url = resolvedURL(for: path)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return size ?? 0
    }

    static func fileModifiedAt(path: String?) -> Date? {
        guard let path, !path.isEmpty else { return nil }
        let url = resolvedURL(for: path)
        return try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    nonisolated static func encryptedObjectBytes() -> Int64 {
        directoryBytes(at: objectsDirectory)
    }

    nonisolated static func encryptedThumbnailBytes() -> Int64 {
        directoryBytes(at: thumbsDirectory)
    }

    nonisolated static func vaultTemporaryBytes() -> Int64 {
        directoryBytes(at: tempDirectory)
    }

    nonisolated static func vaultBytes() -> Int64 {
        directoryBytes(at: vaultDirectory)
    }

    static func availableCapacityForImportantUsage() -> Int64 {
        let values = try? vaultDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static func assetURL(for path: String) -> URL {
        resolvedURL(for: path)
    }

    static func prepareForCloudAssetUpload(path: String?) throws {
        guard let path, !path.isEmpty else { return }
        try setEncryptedFileProtection(at: resolvedURL(for: path))
    }

    static func encryptedFileAttributesForLog(path: String?) -> String {
        guard let path, !path.isEmpty else { return "none" }
        let url = resolvedURL(for: path)
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = attributes[.size] as? NSNumber
        let protection = attributes[.protectionKey] as? FileProtectionType
        return "exists=\(FileManager.default.fileExists(atPath: url.path)) size=\(size?.int64Value ?? -1) protection=\(protection?.rawValue ?? "unknown") path=\(storedPathForLog(path))"
    }

    nonisolated static func normalizedStoredPath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return path }
        if path.hasPrefix("/") {
            if let range = path.range(of: "/Vault/") {
                return String(path[range.upperBound...])
            }

            let url = URL(fileURLWithPath: path).standardizedFileURL
            let vaultPath = vaultDirectory.standardizedFileURL.path
            if url.path.hasPrefix(vaultPath + "/") {
                return String(url.path.dropFirst(vaultPath.count + 1))
            }
        }
        return path
    }

    static func remove(path: String?) {
        guard let path else { return }
        try? FileManager.default.removeItem(at: resolvedURL(for: path))
    }

    nonisolated static func temporaryPlainURL(fileName: String, data: Data) throws -> URL {
        try prepareDirectories()
        let safeName = fileName.replacingOccurrences(of: "/", with: "-")
        let url = tempDirectory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func clearTemporaryFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func replaceItem(at destination: URL, with sourceURL: URL) {
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: sourceURL, to: destination)
        try? setEncryptedFileProtection(at: destination)
    }

    nonisolated static func directoryBytes(at directoryURL: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return 0
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else {
                continue
            }
            let size = values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
            total += Int64(max(0, size))
        }
        return total
    }

    nonisolated private static func setEncryptedFileProtection(at url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: encryptedFileProtection], ofItemAtPath: url.path)
    }

    private nonisolated static func resolvedURL(for storedPath: String) -> URL {
        let candidate: URL
        if let normalized = normalizedStoredPath(storedPath), normalized != storedPath {
            candidate = vaultDirectory.appendingPathComponent(normalized)
        } else if storedPath.hasPrefix("/") {
            candidate = URL(fileURLWithPath: storedPath)
        } else {
            candidate = vaultDirectory.appendingPathComponent(storedPath)
        }

        let resolved = candidate.standardizedFileURL
        let vault = vaultDirectory.standardizedFileURL
        guard resolved.path == vault.path || resolved.path.hasPrefix(vault.path + "/") else {
            return vault.appendingPathComponent(resolved.lastPathComponent)
        }

        return resolved
    }

    nonisolated private static func relativePath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let vaultPath = vaultDirectory.standardizedFileURL.path
        guard path.hasPrefix(vaultPath + "/") else {
            return path
        }
        return String(path.dropFirst(vaultPath.count + 1))
    }

    private nonisolated static func storedPathForLog(_ path: String) -> String {
        normalizedStoredPath(path) ?? path
    }
}

struct AppStorageUsageSnapshot: Equatable {
    static let empty = AppStorageUsageSnapshot(
        appBundleBytes: 0,
        appDataBytes: 0,
        vaultBytes: 0,
        encryptedOriginalBytes: 0,
        thumbnailBytes: 0,
        vaultTemporaryBytes: 0,
        cacheBytes: 0,
        temporaryBytes: 0
    )

    let appBundleBytes: Int64
    let appDataBytes: Int64
    let vaultBytes: Int64
    let encryptedOriginalBytes: Int64
    let thumbnailBytes: Int64
    let vaultTemporaryBytes: Int64
    let cacheBytes: Int64
    let temporaryBytes: Int64

    var totalBytes: Int64 {
        appBundleBytes + appDataBytes
    }

    var otherVaultBytes: Int64 {
        max(0, vaultBytes - encryptedOriginalBytes - thumbnailBytes - vaultTemporaryBytes)
    }

    var otherAppDataBytes: Int64 {
        max(0, appDataBytes - vaultBytes - cacheBytes - temporaryBytes)
    }

    nonisolated static func current() -> AppStorageUsageSnapshot {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let temporaryURL = fileManager.temporaryDirectory

        let documentsBytes = documentsURL.map(VaultFileStore.directoryBytes(at:)) ?? 0
        let applicationSupportBytes = applicationSupportURL.map(VaultFileStore.directoryBytes(at:)) ?? 0
        let cacheBytes = cachesURL.map(VaultFileStore.directoryBytes(at:)) ?? 0
        let temporaryBytes = VaultFileStore.directoryBytes(at: temporaryURL)

        return AppStorageUsageSnapshot(
            appBundleBytes: VaultFileStore.directoryBytes(at: Bundle.main.bundleURL),
            appDataBytes: documentsBytes + applicationSupportBytes + cacheBytes + temporaryBytes,
            vaultBytes: VaultFileStore.vaultBytes(),
            encryptedOriginalBytes: VaultFileStore.encryptedObjectBytes(),
            thumbnailBytes: VaultFileStore.encryptedThumbnailBytes(),
            vaultTemporaryBytes: VaultFileStore.vaultTemporaryBytes(),
            cacheBytes: cacheBytes,
            temporaryBytes: temporaryBytes
        )
    }
}

enum AppStorageUsageCalculator {
    static func currentSnapshot() async -> AppStorageUsageSnapshot {
        await Task.detached(priority: .utility) {
            AppStorageUsageSnapshot.current()
        }.value
    }
}

enum AppStorageUsageFormatter {
    static func localizedFileSize(_ bytes: Int64, locale: Locale = AppLanguage.current.locale) -> String {
        let safeBytes = max(0, bytes)
        let value = Double(safeBytes)
        let kb = 1024.0
        let mb = kb * 1024.0
        let gb = mb * 1024.0

        if value >= gb {
            return "\(localizedNumber(value / gb, minimumFractionDigits: 2, maximumFractionDigits: 2, locale: locale)) GB"
        }
        if value >= mb {
            return "\(localizedNumber(value / mb, minimumFractionDigits: 1, maximumFractionDigits: 1, locale: locale)) MB"
        }
        if value >= kb {
            return "\(localizedNumber(value / kb, minimumFractionDigits: 1, maximumFractionDigits: 1, locale: locale)) KB"
        }
        return "\(safeBytes) B"
    }

    private static func localizedNumber(
        _ value: Double,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int,
        locale: Locale
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maximumFractionDigits)f", value)
    }
}
