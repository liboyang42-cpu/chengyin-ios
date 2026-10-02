import Foundation
import Security
import CryptoKit

/// The journal contains opaque handles and pending proof, never SDK private keys
/// or authentication tokens. Device-only, unlocked-only, non-synchronizing storage.
@MainActor final class NativeEnrollmentKeychainStore: NativeEnrollmentStoring {
    func read(scope: NativeEnrollmentScope) throws -> NativeEnrollmentRecord? {
        var request = try query(scope); request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 196_608 else { throw NativeEnrollmentIssue.storageUnavailable }
        let record = try JSONDecoder().decode(NativeEnrollmentRecord.self, from: data)
        try record.validate(scope: scope); return record
    }
    func write(_ record: NativeEnrollmentRecord) throws {
        try record.validate(scope: record.scope)
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= 196_608 else { throw NativeEnrollmentIssue.storageUnavailable }
        let request = try query(record.scope)
        let values: [String: Any] = [kSecValueData as String: bytes, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(request as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = request; insertion.merge(values) { _, new in new }
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw NativeEnrollmentIssue.storageUnavailable }
        } else if status != errSecSuccess { throw NativeEnrollmentIssue.storageUnavailable }
    }
    private func query(_ scope: NativeEnrollmentScope) throws -> [String: Any] {
        let data = try JSONEncoder().encode([scope.namespace, String(scope.accountID), scope.appID, scope.environment])
        let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "questify.native-enrollment.v1",
            kSecAttrAccount as String: id, kSecAttrSynchronizable as String: false]
    }
}
