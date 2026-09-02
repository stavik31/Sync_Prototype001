import Foundation
import Security

// Stores the Cognito tokens in the iOS Keychain.
//
// Tokens go here rather than in a plain file because they're credentials —
// anyone holding one can act as this user until it expires. Notebook content
// isn't sensitive in the same way, so it lives as ordinary files.
//
// Two entries, keyed by name: "authToken" (the ID token) and "refreshToken".
//
// Worth knowing: every OSStatus is ignored, so a failed write is silent — you
// get nothing back on the next read and no indication why.
struct KeychainManager {

    static func save(token: String, key: String) {
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

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

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
