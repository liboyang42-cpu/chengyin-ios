import Foundation

/// Source P036 prediction choices and relative schedule over the existing native schema.
public struct TemplatePredictionPlan {
    public enum TextField: String { case question, hint }
    public enum TimingField: String, CaseIterable, Identifiable { case closeAtHour, revealDays, revealHour
        public var id: String { rawValue }
    }
    public struct Row: Identifiable { public let id: Int; public let key: String; public let label: String }
    public enum Edit { case text(TextField, String), label(Int, String), add, remove(Int), timing(TimingField, Int) }
    public static let managedFields: Set<String> = ["question", "hint", "options", "closeAtHour", "revealDays", "revealHour"]
    public static let hours = Array(0...23)
    public static let days = Array(0...30)
    public let rows: [Row]
    public let question: String
    public let hint: String
    public let isSupported: Bool
    public let canEdit: Bool
    private let times: [TimingField: Int]
    private let fingerprint: Data?
    public var canAdd: Bool { canEdit && rows.count < 4 }
    public var sameDayConflict: Bool { timing(.revealDays) == 0 && timing(.revealHour) < timing(.closeAtHour) }
    public func timing(_ field: TimingField) -> Int { times[field] ?? (field == .revealDays ? 1 : 20) }
    public init(_ draft: TemplateAdvancedDraft) {
        let object = draft.value["predict"]?.object, values = object ?? [:], rawRows = values["options"]?.array, encoded = Self.snapshot(draft)
        var projected: [Row] = [], validRows = rawRows != nil
        for (index, value) in (rawRows ?? []).enumerated() {
            guard let row = value.object, let key = row["key"]?.string, let label = row["label"]?.string else { validRows = false; continue }
            projected.append(.init(id: index, key: key, label: label))
        }
        var projectedTimes: [TimingField: Int] = [:], validTimes = true
        for field in TimingField.allCases {
            let raw = values[field.rawValue], fallback = field == .revealDays ? 1 : 20
            let nonblank = raw?.string.map { !TemplateAuthoringStory.sourceTrim($0).isEmpty } ?? true
            let candidate: Int? = raw == nil ? fallback : raw?.integer
            guard nonblank, let value = candidate,
                  (field == .revealDays ? Self.days : Self.hours).contains(value) else { validTimes = false; continue }
            projectedTimes[field] = value
        }
        let validText = ["question", "hint"].allSatisfy { values[$0] == nil || values[$0]?.string != nil }
        let supported = object != nil && encoded != nil && validRows && validTimes && validText
        rows = projected; times = projectedTimes; question = values["question"]?.string ?? ""; hint = values["hint"]?.string ?? ""
        fingerprint = encoded; isSupported = supported; canEdit = supported && draft.enabled("predict")
    }
    public func isCurrent(_ draft: TemplateAdvancedDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> TemplateAdvancedDraft? {
        guard canEdit, isCurrent(draft) else { return nil }
        var next = draft
        switch edit {
        case .text(let field, let value): next.set("predict", field.rawValue, .string(value))
        case .label(let index, let value):
            guard rows.contains(where: { $0.id == index }) else { return nil }
            next.setCreatorValue(.predict, path: [.field("options"), .index(index), .field("label")], entry: .string(value))
        case .add:
            guard canAdd, let field = TemplateCreatorSchema.fields(.predict).first(where: { $0.id == "options" }) else { return nil }
            // Reuse the existing unique opaque-key allocator rather than expose editable keys.
            next.addCreatorRow(.predict, path: [.field("options")], field: field)
        case .remove(let index):
            guard rows.contains(where: { $0.id == index }), var values = draft.value["predict"]?.object?["options"]?.array, values.indices.contains(index) else { return nil }
            values.remove(at: index); next.set("predict", "options", .array(values))
        case .timing(let field, let value):
            guard (field == .revealDays ? Self.days : Self.hours).contains(value) else { return nil }
            next.set("predict", field.rawValue, .number(Double(value)))
        }
        return next
    }
    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["predict"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(value)
    }
}
