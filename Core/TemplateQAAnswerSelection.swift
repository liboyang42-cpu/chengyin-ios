import Foundation

/// Local answer configuration over the existing QA wire fields. Reading never normalizes a draft.
public struct TemplateQAAnswerSelection {
    public struct Option: Identifiable, Equatable {
        public let id: Int
        public let label: String
        public let correct: Bool
    }
    public enum Edit { case choose(Int), setMultiple(Bool) }

    public let options: [Option]
    public let isMultiple: Bool
    public let isSupported: Bool
    public let canEdit: Bool
    private let fingerprint: Data?

    public init(_ draft: TemplateAdvancedDraft) {
        let fields = draft.value["qa"]?.object
        let rows = fields?["options"]?.array
        func booleanOrMissing(_ value: TemplateAuthoringJSON?) -> Bool {
            guard let value else { return true }
            if case .bool = value { return true }
            return false
        }
        let supported = fields != nil && rows != nil && (rows?.count ?? 0) <= 4 &&
            booleanOrMissing(fields?["multi"]) && (rows ?? []).allSatisfy { row in
                guard let value = row.object else { return false }
                return booleanOrMissing(value["correct"]) &&
                    (value["label"] == nil || value["label"]?.string != nil)
            }
        fingerprint = Self.snapshot(draft)
        isSupported = supported && fingerprint != nil
        isMultiple = fields?["multi"]?.bool ?? false
        canEdit = isSupported && fields?["enabled"]?.bool == true && fields?["mode"]?.string == "PICK"
        options = supported ? (rows ?? []).enumerated().map { index, row in
            Option(id: index, label: row.object?["label"]?.string ?? "", correct: row.object?["correct"]?.bool ?? false)
        } : []
    }

    /// A choice from a previous list cannot be applied after a reorder, text change, or mode change.
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> TemplateAdvancedDraft? {
        guard canEdit, fingerprint == Self.snapshot(draft),
              var fields = draft.value["qa"]?.object, var rows = fields["options"]?.array else { return nil }
        switch edit {
        case .choose(let index):
            guard rows.indices.contains(index) else { return nil }
            rows = rows.enumerated().map { offset, raw in
                var row = raw.object!
                if isMultiple {
                    if offset == index { row["correct"] = .bool(!(row["correct"]?.bool ?? false)) }
                } else { row["correct"] = .bool(offset == index) }
                return .object(row)
            }
            fields["options"] = .array(rows)
        case .setMultiple(let enabled):
            fields["multi"] = .bool(enabled)
            if !enabled {
                var kept = false
                fields["options"] = .array(rows.map { raw in
                    var row = raw.object!
                    let correct = (row["correct"]?.bool ?? false) && !kept
                    if correct { kept = true }
                    row["correct"] = .bool(correct)
                    return .object(row)
                })
            }
        }
        var next = draft
        next.value["qa"] = .object(fields)
        return next
    }

    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["qa"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }
}
