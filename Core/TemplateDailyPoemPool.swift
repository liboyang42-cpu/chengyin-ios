import Foundation

/// Raw multiline text is presentation state; only canonical [[String]] is persisted.
public struct TemplateDailyPoemPool {
    public struct Row: Identifiable, Equatable {
        public let id: UUID
        public var text: String
        public init(id: UUID = UUID(), text: String) { self.id = id; self.text = text }
    }
    public enum Edit { case add, text(UUID, String), remove(UUID) }
    public struct Update {
        public let draft: TemplateAdvancedDraft
        public let pool: TemplateDailyPoemPool
    }
    public private(set) var rows: [Row]
    public let isSupported: Bool
    public let canEdit: Bool
    public var canAdd: Bool { canEdit && rows.count < 60 }
    private var fingerprint: Data?

    public init(_ draft: TemplateAdvancedDraft) {
        let raw = draft.value["dailySign"]?.object?["poems"], poems = raw?.array
        let encoded = Self.snapshot(draft); fingerprint = encoded
        let supported = (raw == nil || poems != nil) && (poems?.count ?? 0) <= 60 && encoded != nil && (poems ?? []).allSatisfy { poem in
            guard let lines = poem.array else { return false }; return lines.allSatisfy { $0.string != nil }
        }
        isSupported = supported; canEdit = supported && draft.enabled("dailySign")
        rows = supported ? (poems ?? []).map { Row(text: $0.array!.map { $0.string! }.joined(separator: "\n")) } : []
    }
    public static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    public func isCurrent(_ draft: TemplateAdvancedDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> Update? {
        guard canEdit, isCurrent(draft) else { return nil }
        var nextRows = rows
        switch edit {
        case .add:
            guard canAdd else { return nil }; nextRows.append(.init(text: ""))
        case .text(let id, let text):
            guard let index = nextRows.firstIndex(where: { $0.id == id }) else { return nil }; nextRows[index].text = text
        case .remove(let id):
            guard let index = nextRows.firstIndex(where: { $0.id == id }) else { return nil }; nextRows.remove(at: index)
        }
        // Mini rebuilds the entire wire pool on every explicit add/edit/remove action.
        let poems: [TemplateAuthoringJSON] = nextRows.map { .array(Self.lines($0.text).map { .string($0) }) }
        var next = draft; next.set("dailySign", "poems", .array(poems))
        var pool = self; pool.rows = nextRows; pool.fingerprint = Self.snapshot(next)
        return .init(draft: next, pool: pool)
    }
    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["dailySign"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(value)
    }
}
