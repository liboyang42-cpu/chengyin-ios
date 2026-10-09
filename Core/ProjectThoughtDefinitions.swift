import Foundation

public struct ProjectThoughtDefinitions {
    public struct Row: Identifiable {
        public let key: String
        public var name: String
        public var summary: String
        public var need: String
        public var whenTags: Set<String>
        public var doneTags: Set<String>
        fileprivate var source: [String: ProjectEditJSON]
        public var id: String { key }
        public var whenNodeIDs: [Int] { nodeIDs("when") }
        public var doneNodeIDs: [Int] { nodeIDs("doneWhen") }
        private func nodeIDs(_ field: String) -> [Int] {
            (source[field]?.array ?? []).compactMap { $0.object?["op"] == .string("NODE_COMPLETED") ? $0.object?["nodeId"]?.integer : nil }
        }
    }
    public struct TagOption: Identifiable {
        public let tag: String
        public let label: String
        public let retained: Bool
        public var id: String { tag }
    }
    public private(set) var readOnly = false
    public var rows: [Row] = []
    public private(set) var tags: [TagOption] = []
    private let raw: ProjectEditJSON?
    private var original: [Row] = []
    private let state: ProjectInitialState
    public init(raw: ProjectEditJSON?, draft: ProjectEditDraft) {
        self.raw = raw; state = .init(raw: raw)
        do {
            guard !state.readOnly else { throw ProjectEditError.invalidDraft }
            let root: [String: ProjectEditJSON]
            if let text = raw?.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                root = try ApprovedTopicReleaseWire.envelope(Data(text.utf8))
            } else { root = [:] }
            let values: [ProjectEditJSON]
            if let value = root["thoughts"], value != .null { guard let list = value.array, list.count <= 8 else { throw ProjectEditError.invalidDraft }; values = list }
            else { values = [] }
            var seen = Set<String>()
            rows = try values.map { value in
                guard let row = value.object, let key = row["key"]?.text, Self.validKey(key), seen.insert(key).inserted,
                      let name = row["name"]?.text else { throw ProjectEditError.invalidDraft }
                let summary: String
                if let value = row["desc"], value != .null { guard let text = value.text else { throw ProjectEditError.invalidDraft }; summary = text } else { summary = "" }
                let need: String
                if let value = row["need"], value != .null { guard let number = value.integer else { throw ProjectEditError.invalidDraft }; need = String(number) } else { need = "" }
                return .init(key: key, name: name, summary: summary, need: need,
                    whenTags: try Self.conditionTags(row["when"]), doneTags: try Self.conditionTags(row["doneWhen"]), source: row)
            }
            original = rows; tags = Self.options(in: draft)
            var known = Set(tags.map(\.tag))
            for tag in rows.flatMap({ Array($0.whenTags.union($0.doneTags)) }).sorted() where known.insert(tag).inserted {
                tags.append(.init(tag: tag, label: tag, retained: true))
            }
        } catch { readOnly = true; rows = []; original = []; tags = [] }
    }
    private static func trim(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        guard let range = value.range(of: pattern, options: .regularExpression) else { return false }
        return range.lowerBound == value.startIndex && range.upperBound == value.endIndex
    }
    public static func validKey(_ value: String) -> Bool { matches(value, "^[a-z][a-z0-9_]{0,31}$") }
    private static func validTag(_ value: String) -> Bool { matches(value, "^tag\\.[a-z][a-z0-9_]{0,47}$") }
    private static func conditions(_ raw: ProjectEditJSON?) throws -> [ProjectEditJSON] {
        guard let raw, raw != .null else { return [] }
        guard let rows = raw.array, rows.count <= 8 else { throw ProjectEditError.invalidDraft }
        for row in rows {
            guard let value = row.object else { throw ProjectEditError.invalidDraft }
            switch value["op"]?.text {
            case "HAS_TAG": guard let tag = value["value"]?.text, validTag(trim(tag)) else { throw ProjectEditError.invalidDraft }
            case "NODE_COMPLETED": guard let id = value["nodeId"]?.integer, id > 0 else { throw ProjectEditError.invalidDraft }
            default: throw ProjectEditError.invalidDraft // Unknown predicates stay intact/read-only, never stripped.
            }
        }
        return rows
    }
    private static func conditionTags(_ raw: ProjectEditJSON?) throws -> Set<String> {
        Set(try conditions(raw).compactMap { row in
            guard row.object?["op"] == .string("HAS_TAG"), let tag = row.object?["value"]?.text else { return nil }; return trim(tag)
        })
    }
    private static func same(_ lhs: Row, _ rhs: Row) -> Bool {
        lhs.key.utf8.elementsEqual(rhs.key.utf8) && lhs.name.utf8.elementsEqual(rhs.name.utf8) &&
        lhs.summary.utf8.elementsEqual(rhs.summary.utf8) && lhs.need.utf8.elementsEqual(rhs.need.utf8) &&
        lhs.whenTags == rhs.whenTags && lhs.doneTags == rhs.doneTags
    }
    public var isUnchanged: Bool { rows.count == original.count && zip(rows, original).allSatisfy { Self.same($0.0, $0.1) } }
    public var recoveryChanges: [ProjectInitialState.RecoveryChange] { isUnchanged ? [] : state.associatedRecoveryChanges }
    @discardableResult public mutating func add(key: String = "t" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(31))) -> Bool {
        guard !readOnly, rows.count < 8, Self.validKey(key), !rows.contains(where: { $0.key == key }) else { return false }
        rows.append(.init(key: key, name: "", summary: "", need: "120", whenTags: [], doneTags: [], source: [:])); return true
    }
    private static func merging(_ raw: ProjectEditJSON?, selected: Set<String>) throws -> ProjectEditJSON? {
        guard selected.allSatisfy(validTag) else { throw ProjectEditError.invalidDraft }
        let old = try conditions(raw), oldTags = try conditionTags(raw)
        if selected == oldTags { return raw }
        var next = old.filter { row in
            guard row.object?["op"] == .string("HAS_TAG"), let tag = row.object?["value"]?.text else { return true }
            return selected.contains(trim(tag))
        }
        next += selected.subtracting(oldTags).sorted().map { .object(["op": .string("HAS_TAG"), "value": .string($0)]) }
        guard next.count <= 8 else { throw ProjectEditError.invalidDraft }
        return next.isEmpty ? nil : .array(next)
    }
    public func serialized(matching current: ProjectEditJSON?) throws -> ProjectEditJSON? {
        guard !readOnly, rows.count <= 8 else { throw ProjectEditError.invalidDraft }
        // Reuse exact source binding even when no thought was changed.
        if isUnchanged { return try state.serialized(matching: current) }
        var keys = Set<String>()
        let knownTags = Set(tags.map(\.tag))
        let values: [ProjectEditJSON] = try rows.map { row in
            let name = Self.trim(row.name), summary = Self.trim(row.summary), needText = Self.trim(row.need)
            guard Self.validKey(row.key), keys.insert(row.key).inserted, row.whenTags.union(row.doneTags).isSubset(of: knownTags),
                  !name.isEmpty, name.utf16.count <= 20,
                  summary.utf16.count <= 60 else { throw ProjectEditError.invalidDraft }
            let need = needText.isEmpty ? nil : Int(needText)
            guard needText.isEmpty || (need.map { (1...100000).contains($0) } == true) else { throw ProjectEditError.invalidDraft }
            let when = try Self.merging(row.source["when"], selected: row.whenTags)
            let done = try Self.merging(row.source["doneWhen"], selected: row.doneTags)
            let doneConditions = try Self.conditions(done)
            guard need != nil || !doneConditions.isEmpty else { throw ProjectEditError.invalidDraft }
            if let old = original.first(where: { $0.key == row.key }), Self.same(old, row) { return .object(row.source) }
            var next = row.source; next["key"] = .string(row.key)
            if !row.name.utf8.elementsEqual((row.source["name"]?.text ?? "").utf8) || row.source["name"] == nil { next["name"] = .string(name) }
            if !row.summary.utf8.elementsEqual((row.source["desc"]?.text ?? "").utf8) { next["desc"] = summary.isEmpty ? nil : .string(summary) }
            if row.need != (row.source["need"]?.integer.map(String.init) ?? "") { next["need"] = need.map { .number(Decimal($0)) } }
            next["when"] = when; next["doneWhen"] = done
            return .object(next)
        }
        return try state.serialized(replacingThoughts: values, matching: current)
    }
    public func assigningReference(_ key: String, chapterID: String, blockID: String, in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard !readOnly, isUnchanged, rows.contains(where: { $0.key.utf8.elementsEqual(key.utf8) }) else { throw ProjectEditError.invalidDraft }
        _ = try state.serialized(matching: draft.preserved["journeyRules"])
        let chapters = draft.chapters.indices.filter { draft.chapters[$0].id == chapterID }
        guard chapters.count == 1, let ci = chapters.first, draft.chapters[ci].id.utf8.elementsEqual(chapterID.utf8) else { throw ProjectEditError.invalidDraft }
        let blocks = (draft.chapters[ci].blocks ?? []).indices.filter { draft.chapters[ci].blocks![$0].id == blockID }
        guard blocks.count == 1, let bi = blocks.first, let block = draft.chapters[ci].blocks?[bi],
              block.kind == .thought, block.id.utf8.elementsEqual(blockID.utf8) else { throw ProjectEditError.invalidDraft }
        if block.fieldText("thoughtKey").utf8.elementsEqual(key.utf8) { return draft }
        var next = draft; next.chapters[ci].blocks?[bi].setField("thoughtKey", .string(key)); return next
    }
    public static func options(in draft: ProjectEditDraft) -> [TagOption] {
        var result: [TagOption] = [], seen = Set<String>()
        func label(_ value: [String: ProjectEditJSON]) -> String {
            for key in ["label", "text", "title", "question"] { if let text = value[key]?.text, !trim(text).isEmpty { return trim(text) } }; return ""
        }
        func walk(_ raw: ProjectEditJSON, context: [String], depth: Int) {
            guard depth <= 32 else { return }
            if let list = raw.array { for item in list { walk(item, context: context, depth: depth + 1) }; return }
            guard let value = raw.object else { return }
            for effect in value["effects"]?.array ?? [] {
                guard effect.object?["op"] == .string("ADD_TAG"), let rawTag = effect.object?["value"]?.text else { continue }
                let tag = trim(rawTag)
                guard validTag(tag), seen.insert(tag).inserted else { continue }
                let parts = context + [label(value).isEmpty ? tag : label(value)]
                let compact = parts.enumerated().filter { $0.offset == 0 || parts[$0.offset - 1] != $0.element }.map(\.element)
                result.append(.init(tag: tag, label: compact.joined(separator: " · "), retained: false))
            }
            let next = value["options"]?.array != nil && !label(value).isEmpty ? context + [label(value)] : context
            for key in value.keys.sorted() where key != "effects" { walk(value[key]!, context: key == "options" ? next : context, depth: depth + 1) }
        }
        for node in draft.chapters.flatMap(\.nodes) {
            guard let id = node.templateID, id > 0, let info = node.localMetadata["templateInfo"]?.object, info["id"]?.integer == id,
                  let raw = info["advancedConfigJson"]?.text, raw.utf8.count <= 262144,
                  let config = try? ApprovedTopicReleaseWire.envelope(Data(raw.utf8)), config["schemaVersion"] == .number(1) else { continue }
            walk(.object(config), context: trim(node.name).isEmpty ? [] : [trim(node.name)], depth: 0)
        }
        return result
    }
}
