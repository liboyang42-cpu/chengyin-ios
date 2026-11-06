import Foundation

/// Read-only UI preflight. The original authoring validator remains authoritative.
struct CollectSetAuthorValidation {
    enum Issue: String, Hashable {
        case titleRequired, titleTooLong, nodesRequired, tooManyNodes, duplicateNodes, missingNodes, invalidKey
        var key: String { "collectSet.validation." + rawValue }
    }
    let rows: [[Issue]]
    let canSave: Bool
    let hasUnexplainedFailure: Bool
    init(values: [CollectSetAuthorDefinition], draft: ProjectEditDraft) {
        let available = Set(draft.chapters.flatMap(\.nodes).compactMap { $0.localMetadata["id"]?.integer }.filter { $0 > 0 })
        rows = values.map { Self.issues($0, available: available) }
        // Includes original whole-graph, uniqueness, group-count and encoded-size checks.
        // This constructs a value only. It never assigns model.draft or calls a writer.
        canSave = (try? CollectSetAuthoring.applying(values, to: draft)) != nil
        hasUnexplainedFailure = !canSave && rows.allSatisfy(\.isEmpty)
    }
    static func issues(_ value: CollectSetAuthorDefinition, available: Set<Int>) -> [Issue] {
        var result: [Issue] = []
        if value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.titleRequired) }
        if value.title.utf16.count > 120 { result.append(.titleTooLong) }
        if value.nodeIds.isEmpty { result.append(.nodesRequired) }
        if value.nodeIds.count > 200 { result.append(.tooManyNodes) }
        if Set(value.nodeIds).count != value.nodeIds.count { result.append(.duplicateNodes) }
        if value.nodeIds.contains(where: { $0 <= 0 || !available.contains($0) }) { result.append(.missingNodes) }
        if value.key.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) == nil { result.append(.invalidKey) }
        return result
    }
    static func text(_ key: String, locale: Locale) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "CollectSetValidation", locale: locale))
    }
}
