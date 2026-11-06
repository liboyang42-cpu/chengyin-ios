import Foundation

/// Identifies existing saved nodes without changing their names, IDs or selection bindings.
struct CollectSetNodePresentation {
    let locale: Locale
    private let counts: [String: Int]
    init(nodes: [(Int, String)], locale: Locale) {
        self.locale = locale
        counts = Dictionary(grouping: nodes, by: { $0.1.trimmingCharacters(in: .whitespacesAndNewlines) }).mapValues(\.count)
    }
    func label(id: Int, name: String) -> String {
        let comparable = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if comparable.isEmpty { return format("collectSet.node.unnamed", String(id)) }
        if (counts[comparable] ?? 0) > 1 { return format("collectSet.node.named", name, String(id)) }
        return name
    }
    private func format(_ key: String, _ values: String...) -> String {
        let pattern = String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "CollectSetNodeLabels", locale: locale))
        return String(format: pattern, locale: locale, arguments: values.map { $0 as CVarArg })
    }
}
