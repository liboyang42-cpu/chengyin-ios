import Foundation

/// Editing-only profile question composition over the existing questions/options schema.
public struct TemplateProfileQuestionComposition {
    public struct Entry: Identifiable, Equatable {
        public let key: String
        public let label: String
        public var id: String { key }
        public init(key: String, label: String) { self.key = key; self.label = label }
    }
    public struct Question: Identifiable, Equatable {
        public let key: String
        public let label: String
        public let kind: String
        public let options: [Entry]
        public var id: String { key }
    }
    public enum Edit {
        case addQuestion, removeQuestions([Int]), moveQuestions([Int], Int), kind(String, String)
        case addOption(String), removeOptions(String, [Int]), moveOptions(String, [Int], Int)
    }
    public let questions: [Question]
    public let isSupported: Bool
    public let canEdit: Bool
    public var canAddQuestion: Bool { canEdit && questions.count < 8 }
    private let fingerprint: Data?

    public init(_ draft: TemplateAdvancedDraft) {
        let rows = draft.value["profile"]?.object?["questions"]?.array, encoded = Self.snapshot(draft)
        fingerprint = encoded; var used = Set<String>()
        let supported = rows != nil && rows!.count <= 8 && encoded != nil && rows!.allSatisfy { raw in
            guard let row = raw.object, let key = row["key"]?.string,
                  key.range(of: "^[A-Za-z][A-Za-z0-9_]{0,15}$", options: .regularExpression) != nil, used.insert(key).inserted,
                  ["text", "pick"].contains(row["kind"]?.string ?? ""), row["label"] == nil || row["label"]?.string != nil,
                  row["options"] == nil || row["options"]?.array != nil else { return false }
            let options = row["options"]?.array ?? []; var keys = Set<String>()
            return options.count <= 6 && options.allSatisfy { raw in
                guard let option = raw.object, let key = option["key"]?.string,
                      key.range(of: TemplateCreatorSchema.keyPattern, options: .regularExpression) != nil,
                      keys.insert(key).inserted else { return false }
                return option["label"] == nil || option["label"]?.string != nil
            }
        }
        isSupported = supported; canEdit = supported && draft.enabled("profile")
        questions = supported ? rows!.map { raw in
            let row = raw.object!
            let options = (row["options"]?.array ?? []).map { option in Entry(key: option.object!["key"]!.string!, label: option.object?["label"]?.string ?? "") }
            return .init(key: row["key"]!.string!, label: row["label"]?.string ?? "", kind: row["kind"]!.string!, options: options)
        } : []
    }
    public func canAddOption(_ questionKey: String) -> Bool { canEdit && questions.contains { $0.key == questionKey && $0.kind == "pick" && $0.options.count < 6 } }
    /// Include retained options on text questions, just like the Mini helper.
    public func nextOptionKeys(_ count: Int) -> [String] {
        guard isSupported, (1...6).contains(count) else { return [] }
        var used = Set(questions.flatMap { $0.options.map(\.key) }), result: [String] = [], index = 0
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
        while result.count < count {
            let key = index < letters.count ? letters[index] : "opt" + String(index - letters.count + 1)
            if used.insert(key).inserted { result.append(key) }
            index += 1
        }
        return result
    }
    public func isCurrent(_ draft: TemplateAdvancedDraft) -> Bool { fingerprint != nil && fingerprint == Self.snapshot(draft) }
    public func applying(_ edit: Edit, to draft: TemplateAdvancedDraft) -> TemplateAdvancedDraft? {
        guard canEdit, isCurrent(draft) else { return nil }
        var rows = draft.rows("profile", "questions")
        switch edit {
        case .addQuestion:
            guard canAddQuestion else { return nil }
            let used = Set(questions.map(\.key)); var number = questions.count + 1
            while used.contains("q\(number)") { number += 1 }
            rows.append(.object(["key": .string("q\(number)"), "label": .string(""), "kind": .string("text"), "maxLength": .number(12), "required": .bool(true)]))
        case .removeQuestions(let indexes):
            guard let remaining = Self.removing(indexes, from: rows, minimum: 1) else { return nil }; rows = remaining
        case .moveQuestions(let indexes, let destination):
            guard let reordered = Self.moving(indexes, in: rows, to: destination) else { return nil }; rows = reordered
        case .kind(let key, let kind):
            guard ["text", "pick"].contains(kind), let index = questions.firstIndex(where: { $0.key == key }) else { return nil }
            var row = rows[index].object!; row["kind"] = .string(kind); row["required"] = .bool(true)
            if kind == "pick", questions[index].options.count < 2 {
                row["options"] = .array(nextOptionKeys(2).map { .object(["key": .string($0), "label": .string(""), "effects": .array([])]) })
            }
            rows[index] = .object(row)
        case .addOption(let key):
            guard canAddOption(key), let index = questions.firstIndex(where: { $0.key == key }), let optionKey = nextOptionKeys(1).first else { return nil }
            var row = rows[index].object!, options = row["options"]?.array ?? []
            options.append(.object(["key": .string(optionKey), "label": .string(""), "effects": .array([])])); row["options"] = .array(options); rows[index] = .object(row)
        case .removeOptions(let key, let indexes):
            guard let index = questions.firstIndex(where: { $0.key == key && $0.kind == "pick" }) else { return nil }
            var row = rows[index].object!
            guard let remaining = Self.removing(indexes, from: row["options"]?.array ?? [], minimum: 2) else { return nil }
            row["options"] = .array(remaining); rows[index] = .object(row)
        case .moveOptions(let key, let indexes, let destination):
            guard let index = questions.firstIndex(where: { $0.key == key && $0.kind == "pick" }) else { return nil }
            var row = rows[index].object!
            guard let reordered = Self.moving(indexes, in: row["options"]?.array ?? [], to: destination) else { return nil }
            row["options"] = .array(reordered); rows[index] = .object(row)
        }
        var next = draft; next.set("profile", "questions", .array(rows)); return next
    }
    private static func removing(_ indexes: [Int], from rows: [TemplateAuthoringJSON], minimum: Int) -> [TemplateAuthoringJSON]? {
        let selected = Set(indexes)
        guard !selected.isEmpty, selected.count == indexes.count, selected.allSatisfy(rows.indices.contains), rows.count - selected.count >= minimum else { return nil }
        return rows.enumerated().filter { !selected.contains($0.offset) }.map(\.element)
    }
    private static func moving(_ indexes: [Int], in rows: [TemplateAuthoringJSON], to destination: Int) -> [TemplateAuthoringJSON]? {
        let selected = Set(indexes)
        guard !selected.isEmpty, selected.count == indexes.count, selected.allSatisfy(rows.indices.contains), (0...rows.count).contains(destination) else { return nil }
        let values = indexes.sorted().map { rows[$0] }
        var remaining = rows.enumerated().filter { !selected.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: values, at: destination - selected.filter { $0 < destination }.count); return remaining
    }
    private static func snapshot(_ draft: TemplateAdvancedDraft) -> Data? {
        guard let value = draft.value["profile"] else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(value)
    }
}
