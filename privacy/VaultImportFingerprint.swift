import CryptoKit
import Foundation

enum VaultImportFingerprint {
    nonisolated static func digest(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return "sha256:" + hash.map { String(format: "%02x", $0) }.joined()
    }
}
