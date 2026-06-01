import Foundation
import Security

enum KeychainService {
    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
        case itemNotFound
    }

    static func save(
        _ data: Data,
        account: String,
        accessGroup: String? = nil,
        accessibility: CFString = kSecAttrAccessibleWhenUnlocked,
        synchronizable: Bool = false
    ) throws {
        var query = baseQuery(account: account, accessGroup: accessGroup, synchronizable: synchronizable)
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessibility

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func read(account: String, accessGroup: String? = nil, synchronizable: Bool = false) throws -> Data {
        var query = baseQuery(account: account, accessGroup: accessGroup, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        return try read(query: query)
    }

    static func readAny(account: String, accessGroup: String? = nil) throws -> Data {
        var query = baseQuery(account: account, accessGroup: accessGroup, synchronizable: false)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        return try read(query: query)
    }

    private static func read(query: [String: Any]) throws -> Data {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { throw KeychainError.itemNotFound }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return data
    }

    static func delete(account: String, accessGroup: String? = nil, synchronizable: Bool = false) {
        SecItemDelete(baseQuery(account: account, accessGroup: accessGroup, synchronizable: synchronizable) as CFDictionary)
    }

    private static func baseQuery(account: String, accessGroup: String?, synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "privacy.vault",
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue as Any
        }
        return query
    }
}
