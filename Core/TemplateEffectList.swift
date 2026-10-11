import Foundation

/// A typed editor over only the effect-list paths already declared in TemplateCreatorSchema.
public struct TemplateEffectList {
    public static let operations = ["SET", "INC", "ADD_TAG"]
    public struct Row: Identifiable, Equatable {
        public let id: Int
        public let operation: String
        public let variable: String
        public let input: String
    }
    public enum Input { case variable, value }
    public enum Edit {
        case add, remove(Int), move(Int, Int), operation(Int, String), input(Int, Input, String)
    }
    public let family: TemplateCreatorFamily
    public let path: [TemplateCreatorPath]
    public let rows: [Row]
    public let isSupported: Bool
    public let canEdit: Bool
    public var canAdd: Bool { canEdit && rows.count < 16 }
    public let scopeFingerprint: Data?
    private let fingerprint: Data?

    public static func isEffectPath(_ family: TemplateCreatorFamily, _ path: [TemplateCreatorPath]) -> Bool {
        func index(_ position: Int) -> Bool { if case .index(let value) = path[position] { return value >= 0 }; return false }
        if family == .check, path.count == 1 {
            return ["successEffects", "failEffects", "critEffects", "fumbleEffects"].contains { path[0] == .field($0) }
        }
        if family == .qa, path.count == 3 { return path[0] == .field("options") && index(1) && path[2] == .field("effects") }
        if [.profile, .branch].contains(family), path.count == 5 {
            return path[0] == .field(family == .profile ? "questions" : "steps") && index(1) &&
                path[2] == .field("options") && index(3) && path[4] == .field("effects")
        }
        return false
    }
    public init(_ draft: TemplateAdvancedDraft, family: TemplateCreatorFamily, path: [TemplateCreatorPath]) {
        self.family = family; self.path = path
        let raw = draft.creatorValue(family, path: path), values = raw?.array
        func stringOrMissing(_ value: TemplateAuthoringJSON?) -> Bool { value == nil || value?.string != nil }
        let supported = Self.isEffectPath(family, path) &&
            draft.creatorValue(family, path: Array(path.dropLast()))?.object != nil &&
            (raw == nil || values != nil) && (values?.count ?? 0) <= 16 && (values ?? []).allSatisfy { raw in
                guard let row = raw.object, stringOrMissing(row["op"]), stringOrMissing(row["var"]) else { return false }
                guard let value = row["value"] else { return true }
                switch value { case .string: return true; case .number(let number): return number.isFinite; default: return false }
            }
        if supported {
            var scope = draft; scope.setCreatorValue(family, path: path, entry: nil)
            scopeFingerprint = Self.snapshot(scope, family: family)
        } else { scopeFingerprint = nil }
        fingerprint = Self.snapshot(draft, family: family)
        isSupported = supported && fingerprint != nil
        var active = draft.enabled(family.rawValue)
        if family == .qa { active = active && draft.text("qa", "mode") == "PICK" }
        if family == .profile { active = active && draft.creatorValue(family, path: Array(path.prefix(2)))?.object?["kind"]?.string == "pick" }
        if family == .branch { active = active && draft.creatorValue(family, path: Array(path.prefix(2)))?.object?["terminal"] == .bool(false) }
        canEdit = isSupported && active
        rows = supported ? (values ?? []).enumerated().map { index, raw in
            let row = raw.object!
            let input: String
            if let text = row["value"]?.string { input = text }
            else if let number = row["value"]?.number { input = number.rounded() == number ? String(format: "%.0f", number) : String(number) }
            else { input = "" }
            return Row(id: index, operation: row["op"]?.string ?? "", variable: row["var"]?.string ?? "", input: input)
        } : []
    }
    public var validationPrefix: String {
        path.reduce(into: "") { result, part in
            switch part {
            case .field(let name): result += (result.isEmpty ? "" : ".") + name
            case .index(let index): result += "[\(index + 1)]"
            }
        }
    }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> TemplateAdvancedDraft? {
        guard canEdit, fingerprint == Self.snapshot(draft, family: family) else { return nil }
        var values = draft.creatorValue(family, path: path)?.array ?? []
        switch edit {
        case .add:
            guard canAdd else { return nil }
            values.append(.object(["var": .string(""), "op": .string("INC"), "value": .number(1)]))
        case .remove(let index):
            guard values.indices.contains(index) else { return nil }; values.remove(at: index)
        case .move(let from, let to):
            guard values.indices.contains(from), values.indices.contains(to), from != to else { return nil }
            let row = values.remove(at: from); values.insert(row, at: to)
        case .operation(let index, let operation):
            guard values.indices.contains(index), Self.operations.contains(operation) else { return nil }
            var row = values[index].object!
            let value = row["value"]
            if operation == "ADD_TAG" { row["value"] = .string(value?.string ?? "") }
            else { row["value"] = .number(Self.numericTransition(value)) }
            row["op"] = .string(operation); values[index] = .object(row)
        case .input(let index, let field, let text):
            guard values.indices.contains(index) else { return nil }
            var row = values[index].object!
            guard Self.operations.contains(row["op"]?.string ?? "") else { return nil }
            switch field {
            case .variable:
                guard row["op"]?.string != "ADD_TAG" else { return nil }
                row["var"] = .string(text)
            case .value:
                // Valid numeric input has Mini's number shape. Keep incomplete text editable
                // instead of producing nonfinite JSON; the existing validator remains authoritative.
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if row["op"]?.string != "ADD_TAG", !trimmed.isEmpty, let number = Double(trimmed), number.isFinite {
                    row["value"] = .number(number)
                } else { row["value"] = .string(text) }
            }
            values[index] = .object(row)
        }
        var next = draft; next.setCreatorValue(family, path: path, entry: .array(values)); return next
    }
    private static func numericTransition(_ value: TemplateAuthoringJSON?) -> Double {
        if case .number(let number)? = value, number.isFinite { return number }
        if let text = value?.string, !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return 0 }
            if let number = Double(trimmed), number.isFinite { return number }
        }
        return 1
    }
    private static func snapshot(_ draft: TemplateAdvancedDraft, family: TemplateCreatorFamily) -> Data? {
        guard let value = draft.value[family.rawValue] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }
}
