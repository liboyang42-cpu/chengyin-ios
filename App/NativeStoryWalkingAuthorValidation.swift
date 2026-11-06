import Foundation

/// Local, read-only author guidance. Never resolves a place or requests location access.
struct NativeStoryWalkingAuthorValidation {
    enum Issue: String, Hashable {
        case ttl, nodeIdentity, region, label, source, floor, approach, alternative, businessTime, longitude, latitude, datum, closed, originalContract
        var key: String { "walkingValidation." + rawValue }
    }
    let global: [Issue]
    let nodes: [Int: [Issue]]
    let canApply: Bool
    init(_ editor: NativeStoryWalkingAuthorDraft, original: ProjectEditDraft) {
        canApply = (try? editor.applying(to: original)) != nil
        // The old contract is view-only until the original explicit upgrade action.
        guard editor.schema == 2 else { global = []; nodes = [:]; return }
        var global: [Issue] = []
        if let seconds = Int(editor.ttl), String(seconds) == editor.ttl, (1...300).contains(seconds) {} else { global.append(.ttl) }
        if editor.nodes.count > 2000 || Set(editor.nodes.map(\.id)).count != editor.nodes.count { global.append(.nodeIdentity) }
        let available = Set(original.chapters.flatMap(\.nodes).compactMap { $0.localMetadata["id"]?.integer }.filter { $0 > 0 })
        var rows: [Int: [Issue]] = [:]
        for node in editor.nodes {
            var issues = Self.issues(node)
            if !available.contains(node.id) { issues.insert(.nodeIdentity, at: 0) }
            rows[node.id] = issues
        }
        if !canApply && global.isEmpty && rows.values.allSatisfy(\.isEmpty) { global.append(.originalContract) }
        self.global = global; nodes = rows
    }
    static func issues(_ node: NativeStoryWalkingAuthorDraft.Node) -> [Issue] {
        var result: [Issue] = []
        if node.region.range(of: "^[A-Z]{2}$", options: .regularExpression) == nil { result.append(.region) }
        guard let entrance = node.entrance else { return result }
        func valid(_ text: String, _ limit: Int, required: Bool = false) -> Bool {
            text.utf16.count <= limit && !text.contains("\0") && (!required || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if !valid(entrance.label, 300, required: true) { result.append(.label) }
        if !valid(entrance.source, 1000, required: true) { result.append(.source) }
        if !valid(entrance.floor, 100) { result.append(.floor) }
        if !valid(entrance.approach, 2000) { result.append(.approach) }
        if !valid(entrance.alternative, 2000) { result.append(.alternative) }
        if !valid(entrance.businessTime, 1000) { result.append(.businessTime) }
        func coordinate(_ text: String, maximum: Double) -> Bool {
            guard let value = Double(text), value.isFinite, abs(value) <= maximum else { return false }
            return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) != nil
        }
        if !coordinate(entrance.longitude, maximum: 180) { result.append(.longitude) }
        if !coordinate(entrance.latitude, maximum: 90) { result.append(.latitude) }
        if !["WGS84", "GCJ02", "BD09"].contains(entrance.datum) { result.append(.datum) }
        if entrance.closed == nil { result.append(.closed) }
        return result
    }
    static func text(_ issue: Issue, locale: Locale) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: issue.key), table: "WalkingValidation", locale: locale))
    }
}
