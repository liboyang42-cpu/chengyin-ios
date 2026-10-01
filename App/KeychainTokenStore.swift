import Foundation
import Security

/// New native bundle uses its own Keychain namespace. No implicit Flutter session migration.
struct KeychainTokenStore {
    enum StoreError: Error { case status(OSStatus), invalidToken }
    private let service = (Bundle.main.bundleIdentifier ?? "Questify") + ".session"
    private let account = "session-token"
    private var query: [String: Any] {
        [kSecClass as String:kSecClassGenericPassword,
         kSecAttrService as String:service,
         kSecAttrAccount as String:account,
         kSecAttrSynchronizable as String:false]
    }
    func read() throws -> String? {
        var request=query
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
        let status=SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.status(status) }
    }
}
