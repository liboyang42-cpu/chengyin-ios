import Foundation

/// P036 blind-taste options use existing key/label rows and answerKey, with no new row identity field.
public struct TemplateBlindOptions {
    public struct Row: Identifiable, Equatable {
        public let id: Int
        public let key: String
        public let label: String
        public let isAnswer: Bool
    }
    public enum Edit {
        case add, remove(Int), choose(Int), move(Int, Int)
        case updateKey(Int, String), updateLabel(Int, String)
    }
    public let rows: [Row]
    public let isSupported: Bool
    public let canEdit: Bool
    public var canAdd: Bool { canEdit && rows.count < 6 }
    private let fingerprint: Data?

    public init(_ draft: TemplateAdvancedDraft) {
        let fields = draft.value["blindTaste"]?.object, values = fields?["options"]?.array
        func stringOrMissing(_ value: TemplateAuthoringJSON?) -> Bool { value == nil || value?.string != nil }
        let supported = fields != nil && values != nil && (values?.count ?? 0) <= 6 &&
            stringOrMissing(fields?["answerKey"]) && (values ?? []).allSatisfy { raw in
                guard let row = raw.object else { return false }
                return stringOrMissing(row["key"]) && stringOrMissing(row["label"])
            }
        fingerprint = Self.snapshot(draft)
        isSupported = supported && fingerprint != nil
        canEdit = isSupported && fields?["enabled"]?.bool == true
        let answer = fields?["answerKey"]?.string ?? ""
        rows = supported ? (values ?? []).enumerated().map { index, raw in
            let key = raw.object?["key"]?.string ?? ""
            return Row(id: index, key: key, label: raw.object?["label"]?.string ?? "", isAnswer: !key.isEmpty && key == answer)
        } : []
    }
    public func canChoose(_ index: Int) -> Bool {
        guard canEdit, rows.indices.contains(index) else { return false }
        let key = rows[index].key
        return key.range(of: TemplateCreatorSchema.keyPattern, options: .regularExpression) == (key.startIndex..<key.endIndex) &&
            rows.filter { $0.key == key }.count == 1
    }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> TemplateAdvancedDraft? {
        guard canEdit, fingerprint == Self.snapshot(draft), var fields = draft.value["blindTaste"]?.object,
              var values = fields["options"]?.array else { return nil }
        switch edit {
        case .add:
            guard canAdd else { return nil }
            let used = Set(rows.map(\.key))
            guard let key = Array("ABCDEFGHIJ").map(String.init).first(where: { !used.contains($0) }) else { return nil }
            values.append(.object(["key": .string(key), "label": .string("")]))
        case .remove(let index):
            guard values.indices.contains(index) else { return nil }
            let removed = values.remove(at: index).object!
            if (fields["answerKey"]?.string ?? "") == (removed["key"]?.string ?? "") {
                fields["answerKey"] = .string(values.first?.object?["key"]?.string ?? "")
            }
        case .move(let from, let to):
            guard values.indices.contains(from), values.indices.contains(to), from != to else { return nil }
            let row = values.remove(at: from); values.insert(row, at: to)
        case .choose(let index):
            guard canChoose(index) else { return nil }
            fields["answerKey"] = .string(rows[index].key)
        case .updateKey(let index, let text):
            guard values.indices.contains(index) else { return nil }
            var row = values[index].object!
            let previousKey = row["key"]?.string ?? ""
            row["key"] = .string(text); values[index] = .object(row)
            if (fields["answerKey"]?.string ?? "") == previousKey { fields["answerKey"] = .string(text) }
        case .updateLabel(let index, let text):
            guard values.indices.contains(index) else { return nil }
            var row = values[index].object!; row["label"] = .string(text); values[index] = .object(row)
        }
        fields["options"] = .array(values)
        var next = draft; next.value["blindTaste"] = .object(fields)
        return next
    }
    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["blindTaste"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }
}
