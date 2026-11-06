import Foundation
import Security

/// Attributes only, same existing service and entitlements as ProjectEditSecureStorage.
/// No token service, access-group override, data enumeration, write, or migration.
@MainActor enum NativeChannelReportJournalKeys {
    static func read(scope: RegionalSessionStorageScope, context: RuntimeDependencyContext) throws -> [String] {
        try read(scope: scope, context: context) { query in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result)
        }
    }
    /// Injectable boundary for mock tests; tests must not query a real Keychain.
    static func read(scope: RegionalSessionStorageScope, context: RuntimeDependencyContext,
                     copyMatching: ([String: Any]) -> (OSStatus, CFTypeRef?)) throws -> [String] {
        guard scope.service.utf8.elementsEqual(context.session.namespace.utf8),
              context.market == .china, context.session.accountID > 0 else { throw ProjectEditError.persistenceUnavailable }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: scope.service + ".project-editor",
            kSecAttrSynchronizable as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        let (status, result) = copyMatching(query)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let attributes = result as? [[String: Any]] else {
            throw ProjectEditError.persistenceUnavailable
        }
        return try attributes.compactMap { item in
            guard let key = item[kSecAttrAccount as String] as? String else { throw ProjectEditError.persistenceUnavailable }
            return NativeChannelReportJournalLocator.conversationID(in: key, context: context) == nil ? nil : key
        }
    }
}

/// Independent reporter-only assembly. No history, membership, SEND or report POST
/// grant is accepted as a receipt grant, and no server hint extends the issued set.
@MainActor enum NativeChannelReportRecoveryAssembly {
    static func make(factory: BusinessRuntimeFactory,
                     currentFactory: @escaping () -> BusinessRuntimeFactory?,
                     storage: any ProjectEditDataStorage, journalKeys: @escaping () throws -> [String],
                     current: @escaping () -> Bool, unauthorized: @escaping () -> Void) -> NativeChannelReportRecoveryDirectory? {
        let features: Set<BusinessRuntimeFeature> = [.imChannelReportReceipt]
        let issued = factory.routes(features), context = factory.captured
        guard !issued.isEmpty else { return nil }
        let live: () -> Bool = {
            guard current(), let latest = currentFactory(), latest.captured == context else { return false }
            return latest.routes(features) == issued
        }
        guard live() else { return nil }
        return try? NativeChannelReportRecoveryDirectory(context: context, transport: factory.client(features),
            storage: storage, journalKeys: journalKeys, current: live,
            permitsRead: { path in live() && issued.contains(where: { $0.method == "GET" && $0.path == path }) },
            unauthorized: { if live() { unauthorized() } })
    }
}
