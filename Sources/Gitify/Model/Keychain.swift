import Foundation
import Security

/// Minimal Keychain wrapper for storing secrets (hosting tokens, AI API keys, etc.).
enum Keychain {
    private static let defaultService = "com.gitify.accounts"

    static func set(_ token: String, account: String, service: String = "com.gitify.accounts") {
        delete(account: account, service: service)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
        ]
        // Use a permissive access control so unsigned debug builds don\u{2019}t trigger
        // repeated keychain authorisation prompts on every relaunch.
        if let access = SecAccessCreateWithOwnerAndACL(
            service: service, account: account
        ) {
            query[kSecAttrAccess as String] = access
        }
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(account: String, service: String = "com.gitify.accounts") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(account: String, service: String = "com.gitify.accounts") {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Creates a SecAccess that allows any application to read the keychain item,
    /// avoiding per-binary ACL checks that cause prompts for unsigned debug builds.
    private static func SecAccessCreateWithOwnerAndACL(service: String, account: String) -> SecAccess? {
        var access: SecAccess?
        let label = "\(service).\(account)" as CFString
        // An empty trusted-apps list means "allow access by any application".
        let status = SecAccessCreate(label, [] as CFArray, &access)
        guard status == errSecSuccess else { return nil }
        return access
    }
}
