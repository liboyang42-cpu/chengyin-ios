import Foundation
import Security

/// Device-only protected storage. No Flutter-key import, cloud sync, plaintext file or token storage.
@MainActor final class RoamHistoryKeychainStorage: RoamHistoryDataStoring {
    private let service = (Bundle.main.bundleIdentifier ?? "Questify") + ".roam-history"
    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false]
    }
    func read(key: String) throws -> Data? {
        var request = query(key)
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw RoamExperienceFailure.historyUnreadable }
        return data
    }
    func write(_ data: Data, key: String) throws {
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(key) as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query(key); insertion.merge(values) { _, new in new }
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw RoamExperienceFailure.historyWriteFailed }
        } else if status != errSecSuccess { throw RoamExperienceFailure.historyWriteFailed }
    }
}
