import Foundation

/// Creator-local occurrence identities; existing pricePair wire rows remain unchanged.
public struct TemplatePictureChoices {
    public struct Row: Identifiable {
        public let id: UUID
        fileprivate var value: [String: TemplateAuthoringJSON]
        public var wireID: String { value["id"]?.string ?? "" }
        public var name: String { value["name"]?.string ?? "" }
        public var imageURL: String { value["imageUrl"]?.string ?? "" }
        public var isCorrect: Bool { value["correct"]?.bool ?? false }
    }
    public enum TextField: Equatable { case name, imageURL }
    public enum Edit { case add, text(UUID, TextField, String), choose(UUID), remove(UUID), move(UUID, Int) }
    public struct Update { public let draft: TemplateAdvancedDraft; public let choices: TemplatePictureChoices }
    public private(set) var rows: [Row]
    public let isSupported: Bool
    public let canEdit: Bool
    public var canAdd: Bool { canEdit && rows.count < 8 }
    public var correctCount: Int { rows.filter(\.isCorrect).count }
    private var fingerprint: Data?

    public init(_ draft: TemplateAdvancedDraft) {
        let raw = draft.value["pricePair"]?.object?["items"]?.array, encoded = Self.snapshot(draft)
        let supported = raw != nil && (raw?.count ?? 0) <= 8 && encoded != nil && (raw ?? []).allSatisfy { rawRow in
            guard let row = rawRow.object else { return false }
            for key in ["id", "name", "imageUrl"] where row[key] != nil && row[key]?.string == nil { return false }
            if let correct = row["correct"] { guard case .bool = correct else { return false } }
            return true
        }
        fingerprint = encoded; isSupported = supported; canEdit = supported && draft.enabled("pricePair")
        rows = supported ? (raw ?? []).map { .init(id: UUID(), value: $0.object!) } : []
    }
    public func isCurrent(_ draft: TemplateAdvancedDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> Update? {
        guard canEdit, isCurrent(draft) else { return nil }
        var nextRows = rows
        switch edit {
        case .add:
            guard canAdd, let field = TemplateCreatorSchema.fields(.pricePair).first(where: { $0.id == "items" }) else { return nil }
            // Keep the native schema's established defaults and collision-free wire ID allocator.
            var added = draft; added.addCreatorRow(.pricePair, path: [.field("items")], field: field)
            guard let value = added.value["pricePair"]?.object?["items"]?.array?.last?.object else { return nil }
            nextRows.append(.init(id: UUID(), value: value))
        case .text(let id, let field, let text):
            guard let index = nextRows.firstIndex(where: { $0.id == id }) else { return nil }
            nextRows[index].value[field == .name ? "name" : "imageUrl"] = .string(text)
        case .choose(let id):
            guard nextRows.contains(where: { $0.id == id }) else { return nil }
            for index in nextRows.indices { nextRows[index].value["correct"] = .bool(nextRows[index].id == id) }
        case .remove(let id):
            guard let index = nextRows.firstIndex(where: { $0.id == id }) else { return nil }; nextRows.remove(at: index)
        case .move(let id, let offset):
            guard offset == -1 || offset == 1, let index = nextRows.firstIndex(where: { $0.id == id }), nextRows.indices.contains(index + offset) else { return nil }
            let row = nextRows.remove(at: index); nextRows.insert(row, at: index + offset)
        }
        var next = draft; next.set("pricePair", "items", .array(nextRows.map { .object($0.value) }))
        var choices = self; choices.rows = nextRows; choices.fingerprint = Self.snapshot(next)
        return .init(draft: next, choices: choices)
    }
    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["pricePair"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(value)
    }
}
