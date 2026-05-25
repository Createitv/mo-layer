import Foundation

enum VaultFileStore {
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
        return url.path
    }

    static func writeEncryptedThumb(_ data: Data, itemId: String) throws -> String {
        try prepareDirectories()
        let url = thumbsDirectory.appendingPathComponent("\(itemId).thumb.enc")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url.path
    }

    static func copyEncryptedObject(from sourceURL: URL, itemId: String) throws -> String {
        try prepareDirectories()
        let destination = objectsDirectory.appendingPathComponent("\(itemId).enc")
        replaceItem(at: destination, with: sourceURL)
        return destination.path
    }

    static func copyEncryptedThumb(from sourceURL: URL, itemId: String) throws -> String {
        try prepareDirectories()
        let destination = thumbsDirectory.appendingPathComponent("\(itemId).thumb.enc")
        replaceItem(at: destination, with: sourceURL)
        return destination.path
    }

    static func read(path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    static func remove(path: String?) {
        guard let path else { return }
        try? FileManager.default.removeItem(atPath: path)
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
}
