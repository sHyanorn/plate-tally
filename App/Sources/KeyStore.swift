import Core
import Foundation
import Security

#if DEBUG
import Synchronization
#endif

/// Where the API key lives. The package never holds the key (R23): the transport reads it here.
protocol KeyStore: Sendable {
    func read() throws(KeychainError) -> String?
    func save(_ key: String) throws(KeychainError)
    func remove() throws(KeychainError)
}

struct KeychainError: PlateError {
    let operation: String
    let status: OSStatus

    var what: String { "the keychain cannot \(operation) the key" }
    var expected: String { "status 0, success" }
    var saw: String {
        let text = SecCopyErrorMessageString(status, nil).map { $0 as String }
        return "status \(status)" + (text.map { ", \($0)" } ?? "")
    }
}

struct KeychainKeyStore: KeyStore {
    /// The service keeps the item apart from other apps and, in tests, from other runs.
    let service: String
    private static let account = "anthropic-api-key"

    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func read() throws(KeychainError) -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(operation: "read", status: status) }
        guard let data = found as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeychainError(operation: "decode", status: errSecDecode)
        }
        return key
    }

    func save(_ key: String) throws(KeychainError) {
        let data = Data(key.utf8)
        var item = identity
        item[kSecValueData as String] = data
        // Not synced, and it does not move to another device.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        var status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw KeychainError(operation: "save", status: status) }
    }

    func remove() throws(KeychainError) {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: "remove", status: status)
        }
    }
}

#if DEBUG
/// Stands in for the keychain in the tests, which must not touch the real one.
final class MemoryKeyStore: KeyStore {
    private let key: Mutex<String?>

    init(_ key: String? = nil) { self.key = Mutex(key) }

    func read() -> String? { key.withLock { $0 } }
    func save(_ key: String) { self.key.withLock { $0 = key } }
    func remove() { key.withLock { $0 = nil } }
}
#endif
