import Foundation
import Security

// Stores the Cognito tokens in the iOS Keychain.
//
// Tokens go here rather than in a plain file because they're credentials —
// anyone holding one can act as this user until it expires. Notebook content
// isn't sensitive in the same way, so it lives as ordinary files.
//
// Two entries, keyed by name: "authToken" (the ID token) and "refreshToken".
struct KeychainManager {

    // Deletes any existing entry under this key first — SecItemAdd fails if one
    // already exists, so this is really "overwrite", not just "insert".
    // The OSStatus from each call is only used as a success/fail Bool; the
    // actual code is discarded, so a failure here never says why it failed.
    static func save(token: String, key: String) -> Bool {
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    // kSecMatchLimitOne caps this at a single result — there should only ever
    // be one item per key anyway, since save() always deletes before adding.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }

    // errSecItemNotFound counts as success — deleting something that's already
    // gone should be a no-op, not a failure, so callers can call this freely.
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
