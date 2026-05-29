import Foundation
import OSLog

enum VaultFileStore {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.landlady.www.privacy", category: "VaultFileStore")

    static var vaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Vault", isDirectory: true)
    }

    static var objectsDirectory: URL {
        vaultDirectory.appendingPathComponent("objects", isDirectory: true)
    }

    static var thumbsDirectory: URL {
        vaultDirectory.appendingPathComponent("thumbs", isDirectory: true)
    }

    static var tempDirectory: URL {
        vaultDirectory.appendingPathComponent("temp", isDirectory: true)
    }

    static func prepareDirectories() throws {
        try [vaultDirectory, objectsDirectory, thumbsDirectory, tempDirectory].forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    static func writeEncryptedObject(_ data: Data, itemId: String) throws -> String {
        try prepareDirectories()
        let url = objectsDirectory.appendingPathComponent("\(itemId).enc")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        logger.debug("Wrote encrypted object for item \(itemId, privacy: .public)")
        return relativePath(for: url)
    }

    static func writeEncryptedThumb(_ data: Data, itemId: String) throws -> String {
        try prepareDirectories()
        let url = thumbsDirectory.appendingPathComponent("\(itemId).thumb.enc")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
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

    static func read(path: String) throws -> Data {
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

    static func assetURL(for path: String) -> URL {
        resolvedURL(for: path)
    }

    static func normalizedStoredPath(_ path: String?) -> String? {
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

    static func temporaryPlainURL(fileName: String, data: Data) throws -> URL {
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
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
    }

    private static func resolvedURL(for storedPath: String) -> URL {
        if let normalized = normalizedStoredPath(storedPath), normalized != storedPath {
            return vaultDirectory.appendingPathComponent(normalized)
        }

        if storedPath.hasPrefix("/") {
            return URL(fileURLWithPath: storedPath)
        }

        return vaultDirectory.appendingPathComponent(storedPath)
    }

    private static func relativePath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let vaultPath = vaultDirectory.standardizedFileURL.path
        guard path.hasPrefix(vaultPath + "/") else {
            return path
        }
        return String(path.dropFirst(vaultPath.count + 1))
    }

    private static func storedPathForLog(_ path: String) -> String {
        normalizedStoredPath(path) ?? path
    }
}
