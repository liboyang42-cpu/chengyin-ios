import Foundation
import Security

/// Deployment-scoped native Keychain; no implicit legacy/Flutter/cross-realm migration.
struct KeychainTokenStore {
    enum StoreError: Error { case status(OSStatus), invalidToken, unconfigured }
    private let scope:RegionalSessionStorageScope?
    init(scope:RegionalSessionStorageScope?) { self.scope=scope }
    private let account = "session-token"
    private func query() throws -> [String: Any] {
        guard let scope else { throw StoreError.unconfigured }
        return [kSecClass as String:kSecClassGenericPassword,
         kSecAttrService as String:scope.service,
         kSecAttrAccount as String:account,
         kSecAttrSynchronizable as String:false]
    }
    func read() throws -> String? {
        guard scope != nil else { return nil }
        var request=try query()
        request[kSecReturnData as String]=true
        request[kSecMatchLimit as String]=kSecMatchLimitOne
        var result: CFTypeRef?
        let status=SecItemCopyMatching(request as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.status(status) }
        guard let data=result as? Data, let value=String(data:data,encoding:.utf8), !value.isEmpty else { throw StoreError.invalidToken }
        return value
    }
    func write(_ token:String) throws {
        guard !token.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw StoreError.invalidToken }
        let query=try query()
        let values:[String:Any]=[kSecValueData as String:Data(token.utf8),
                                kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status=SecItemUpdate(query as CFDictionary,values as CFDictionary)
        if status == errSecItemNotFound {
            var insertion=query;insertion.merge(values){_,new in new}
            let added=SecItemAdd(insertion as CFDictionary,nil)
            guard added == errSecSuccess else { throw StoreError.status(added) }
        } else if status != errSecSuccess { throw StoreError.status(status) }
    }
    func clear() throws {
        guard scope != nil else { return }
        let query=try query()
        let status=SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.status(status) }
    }
}
