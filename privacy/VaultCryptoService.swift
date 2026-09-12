import CryptoKit
import Foundation
import Security
import UniformTypeIdentifiers

enum VaultCryptoService {
    enum CryptoError: Error {
        case missingRootKey
        case invalidSealedBox
        case invalidString
        case invalidRecoveryKey
    }

    static let rootKeyAccount = "vault.root.key"
    static let recoveryKeyAccount = "vault.recovery.key"
    private static let synchronizableRootKeyAccount = "vault.root.key.icloud"

    static func hasRootKey() -> Bool {
        (try? KeychainService.read(account: rootKeyAccount)) != nil
    }

    static func hasRecoverableRootKey() -> Bool {
        if hasRootKey() {
            return true
        }
        guard let data = try? KeychainService.read(account: synchronizableRootKeyAccount, synchronizable: true) else {
            return false
        }
        return data.count == 32
    }

    static func ensureRootKey() throws -> SymmetricKey {
        if let data = try? KeychainService.read(account: rootKeyAccount) {
            return SymmetricKey(data: data)
        }
        if let restored = try? restoreRootKeyFromICloudKeychain() {
            return restored
        }
        let keyData = randomData(count: 32)
        try KeychainService.save(keyData, account: rootKeyAccount)
        try? syncRootKeyToICloudKeychain(rootKeyData: keyData)

        let recoveryKey = makeRecoveryKey()
        try KeychainService.save(Data(recoveryKey.utf8), account: recoveryKeyAccount)
        return SymmetricKey(data: keyData)
    }

    static func makeRootKeyPackage(recoveryKey: String? = nil) throws -> Data {
        let rootKeyData: Data
        if let data = try? KeychainService.read(account: rootKeyAccount) {
            rootKeyData = data
        } else {
            _ = try ensureRootKey()
            rootKeyData = try KeychainService.read(account: rootKeyAccount)
        }

        let recoveryKey = normalizedRecoveryKey(recoveryKey ?? currentRecoveryKey())
        guard !recoveryKey.isEmpty, recoveryKey != L.string("Not Generated") else {
            throw CryptoError.invalidRecoveryKey
        }
        return try encrypt(rootKeyData, using: recoveryWrappingKey(from: recoveryKey))
    }

    @discardableResult
    static func restoreRootKey(from package: Data, recoveryKey: String) throws -> SymmetricKey {
        let rootKey = try previewRootKey(from: package, recoveryKey: recoveryKey)
        try installRootKey(rootKey, recoveryKey: recoveryKey)
        return rootKey
    }

    static func previewRootKey(from package: Data, recoveryKey: String) throws -> SymmetricKey {
        let normalized = normalizedRecoveryKey(recoveryKey)
        guard !normalized.isEmpty else { throw CryptoError.invalidRecoveryKey }
        let rootKeyData = try decrypt(package, using: recoveryWrappingKey(from: normalized))
        guard rootKeyData.count == 32 else { throw CryptoError.invalidRecoveryKey }
        return SymmetricKey(data: rootKeyData)
    }

    static func installRootKey(_ rootKey: SymmetricKey, recoveryKey: String) throws {
        let normalized = normalizedRecoveryKey(recoveryKey)
        guard !normalized.isEmpty else { throw CryptoError.invalidRecoveryKey }
        let rootKeyData = rootKey.withUnsafeBytes { Data($0) }
        guard rootKeyData.count == 32 else { throw CryptoError.invalidRecoveryKey }
        try KeychainService.save(rootKeyData, account: rootKeyAccount)
        try? syncRootKeyToICloudKeychain(rootKeyData: rootKeyData)
        try KeychainService.save(Data(normalized.utf8), account: recoveryKeyAccount)
    }

    @discardableResult
    static func restoreRootKeyFromICloudKeychain() throws -> SymmetricKey {
        let rootKeyData = try KeychainService.read(account: synchronizableRootKeyAccount, synchronizable: true)
        guard rootKeyData.count == 32 else { throw CryptoError.invalidRecoveryKey }
        try KeychainService.save(rootKeyData, account: rootKeyAccount)
        return SymmetricKey(data: rootKeyData)
    }

    static func syncRootKeyToICloudKeychain() throws {
        let rootKeyData = try KeychainService.read(account: rootKeyAccount)
        try syncRootKeyToICloudKeychain(rootKeyData: rootKeyData)
    }

    static func canRestoreRootKey(from package: Data, recoveryKey: String? = nil) -> Bool {
        let normalized = normalizedRecoveryKey(recoveryKey ?? currentRecoveryKey())
        guard !normalized.isEmpty, normalized != normalizedRecoveryKey(L.string("Not Generated")) else {
            return false
        }
        guard let data = try? decrypt(package, using: recoveryWrappingKey(from: normalized)) else {
            return false
        }
        return data.count == 32
    }


    static func currentRecoveryKey() -> String {
        guard let data = try? KeychainService.read(account: recoveryKeyAccount),
              let value = String(data: data, encoding: .utf8) else {
            return L.string("Not Generated")
        }
        return value
    }

    nonisolated static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(data, using: key)
        guard let combined = box.combined else { throw CryptoError.invalidSealedBox }
        return combined
    }

    nonisolated static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    static func encryptString(_ value: String, using key: SymmetricKey) throws -> Data {
        try encrypt(Data(value.utf8), using: key)
    }

    static func decryptString(_ data: Data, using key: SymmetricKey) throws -> String {
        let decrypted = try decrypt(data, using: key)
        guard let value = String(data: decrypted, encoding: .utf8) else {
            throw CryptoError.invalidString
        }
        return value
    }

    static func encryptCodable<T: Encodable>(_ value: T, using key: SymmetricKey) throws -> Data {
        let data = try JSONEncoder().encode(value)
        return try encrypt(data, using: key)
    }

    static func decryptCodable<T: Decodable>(_ type: T.Type, from data: Data, using key: SymmetricKey) throws -> T {
        let decrypted = try decrypt(data, using: key)
        return try JSONDecoder().decode(type, from: decrypted)
    }

    static func newFileKey() -> SymmetricKey {
        SymmetricKey(data: randomData(count: 32))
    }

    static func wrapFileKey(_ fileKey: SymmetricKey, rootKey: SymmetricKey) throws -> Data {
        let data = fileKey.withUnsafeBytes { Data($0) }
        return try encrypt(data, using: rootKey)
    }

    nonisolated static func unwrapFileKey(_ wrapped: Data, rootKey: SymmetricKey) throws -> SymmetricKey {
        let data = try decrypt(wrapped, using: rootKey)
        return SymmetricKey(data: data)
    }

    static func randomData(count: Int) -> Data {
        precondition(count > 0, "Random byte count must be positive")
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "Secure random generation failed with status \(status)")
        return Data(bytes)
    }

    private static func makeRecoveryKey() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var result = ""
        let bytes = [UInt8](randomData(count: 24))
        for index in bytes.indices {
            if index > 0 && index % 4 == 0 { result.append("-") }
            result.append(alphabet[Int(bytes[index]) % alphabet.count])
        }
        return result
    }

    private static func normalizedRecoveryKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func syncRootKeyToICloudKeychain(rootKeyData: Data) throws {
        try KeychainService.save(
            rootKeyData,
            account: synchronizableRootKeyAccount,
            accessibility: kSecAttrAccessibleAfterFirstUnlock,
            synchronizable: true
        )
    }

    private static func recoveryWrappingKey(from recoveryKey: String) -> SymmetricKey {
        let material = SymmetricKey(data: Data(recoveryKey.utf8))
        let salt = Data("Palimpsest.iCloud.RootKey.v1".utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: material,
            salt: salt,
            info: Data("VaultManifest.encryptedRootKeyPackage".utf8),
            outputByteCount: 32
        )
    }
}
