import Foundation
import Security

/// Uses the same reviewed deployment namespace as session storage, with a distinct service.
/// Upload metadata is device-only, non-synchronizable, unlocked-only Keychain items. Never migrate
/// Flutter buckets or cross-region drafts implicitly. Keychain failures remain visible.
@MainActor final class ImageUploadSecureStorage {
    private let scope: RegionalSessionStorageScope?
    init(scope: RegionalSessionStorageScope?) { self.scope = scope }
    private func query(_ key: String) throws -> [String: Any] {
        guard let scope else { throw ImageUploadJournalFailure.unavailable }
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: scope.service + ".image-upload-journal",
                kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false]
    }
    func read(_ key: String) throws -> Data? {
        var request = try query(key); request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ImageUploadJournalFailure.unavailable }
        return data
    }
    func write(_ data: Data, key: String) throws {
        let request = try query(key)
        let values: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(request as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = request; insertion.merge(values) { _, new in new }
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw ImageUploadJournalFailure.unavailable }
        } else if status != errSecSuccess { throw ImageUploadJournalFailure.unavailable }
    }
}
