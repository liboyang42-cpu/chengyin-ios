import SwiftUI
import Security

extension GlobalSearchKind {
    var titleKey: LocalizedStringKey { LocalizedStringKey("searchMap.kind." + rawValue) }
    var symbol: String {
        switch self { case .topic: return "point.topleft.down.to.point.bottomright.curvepath"
        case .activity: return "calendar"; case .club: return "person.3"; case .merchant: return "storefront" }
    }
}
struct SearchMapIssue: View {
    let key: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 12) {
            Label(LocalizedStringKey(key), systemImage: key.contains("unauthorized") ? "lock" : "exclamationmark.circle")
                .fixedSize(horizontal: false, vertical: true)
            if let retry { Button("searchMap.retry", action: retry).buttonStyle(.bordered).frame(minHeight: 44) }
        }.padding().frame(maxWidth: .infinity).accessibilityIdentifier("searchMap.issue")
    }
    static func key(_ error: Error) -> String {
        switch error as? APIError {
        case .unauthorized: return "searchMap.unauthorized"
        case .notConfigured, .invalidConfiguration: return "searchMap.notConfigured"
        case .invalidRequest: return "searchMap.invalidInput"
        default: return "searchMap.failed"
        }
    }
}
struct SearchMapCard: View {
    let row: GlobalSearchRow
    let offline: Bool
    var body: some View {
        QuestifyImageEntityCard(imageSource: offline ? nil : row.imageURL, title: row.title, subtitle: row.detail,
                               fallbackTitle: "searchMap.untitled", fallbackSymbol: row.kind.symbol, minimumHeight: 230) {
            Label(row.kind.titleKey, systemImage: row.kind.symbol)
            if !row.tags.isEmpty { Text(verbatim: row.tags.joined(separator: " · ")) }
        }.accessibilityElement(children: .combine)
    }
}
/// Match the source's local secure-storage history rather than writing queries to ordinary defaults.
/// A nil namespace (fixtures/unconfigured) is memory-only and never touches Keychain.
@MainActor final class SearchMapLocalHistory {
    private(set) var failed = false
    private func query(_ namespace: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: namespace + ".search.history", kSecAttrAccount as String: "recent"]
    }
    func read(namespace: String?) -> [String] {
        failed = false
        guard let namespace else { return [] }
        var query = query(namespace); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data,
              let values = try? JSONDecoder().decode([String].self, from: data) else { failed = true; return [] }
        return Array(values.prefix(10))
    }
    func add(_ keyword: String, namespace: String?, current: [String]) -> [String] {
        failed = false
        let next = SearchHistoryPolicy.adding(keyword, to: current)
        guard let namespace else { return next }
        guard let data = try? JSONEncoder().encode(next) else { failed = true; return next }
        let base = query(namespace)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = base; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            failed = SecItemAdd(item as CFDictionary, nil) != errSecSuccess
        } else { failed = status != errSecSuccess }
        return next
    }
    func clear(namespace: String?) -> Bool {
        failed = false
        guard let namespace else { return true }
        let status = SecItemDelete(query(namespace) as CFDictionary)
        failed = status != errSecSuccess && status != errSecItemNotFound
        return !failed
    }
}
