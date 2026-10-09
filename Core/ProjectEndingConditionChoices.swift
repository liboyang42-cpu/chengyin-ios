import Foundation

/// Sources for an existing ending predicate only. Does not change its operator or fallback semantics.
public enum ProjectEndingConditionChoices {
    public struct Choice: Identifiable {
        public enum Kind: String { case thought, tag, node }
        public let id: String
        public let kind: Kind
        public let label: String
        public let value: ProjectEditJSON
    }
    public struct Target {
        public let chapterID: String
        public let index: Int
        public let conditionBytes: Data
        public let operation: String
        public init(draft: ProjectEditDraft, chapterID: String, index: Int) throws {
            guard let value = ProjectEndingConditionChoices.condition(draft, chapterID: chapterID, index: index),
                  let op = value["op"]?.text, ["HAS_TAG", "NODE_COMPLETED"].contains(op),
                  let bytes = ProjectEditPendingMaterials.exactData(ProjectEditJSON.object(value)) else { throw ProjectEditError.invalidDraft }
            self.chapterID = chapterID; self.index = index; conditionBytes = bytes; operation = op
        }
    }
    private static func chapterIndex(_ draft: ProjectEditDraft, id: String) -> Int? {
        guard draft.product == .city, !id.isEmpty else { return nil }
        let indices = draft.chapters.indices.filter { draft.chapters[$0].id == id }
        guard indices.count == 1, let index = indices.first, draft.chapters[index].id.utf8.elementsEqual(id.utf8),
              draft.chapters[index].nodes.isEmpty, draft.chapters[index].preserved["opening"] != .bool(true) else { return nil }
        return index
    }
    public static func condition(_ draft: ProjectEditDraft, chapterID: String, index: Int) -> [String: ProjectEditJSON]? {
        guard let ci = chapterIndex(draft, id: chapterID), let ending = draft.chapters[ci].preserved["ending"]?.object,
              ending["fallback"] == nil || ending["fallback"] == .null || ending["fallback"] == .bool(false),
              let rows = ending["when"]?.array, rows.indices.contains(index) else { return nil }
        return rows[index].object
    }
    public static func choices(in draft: ProjectEditDraft, operation: String) -> [Choice] {
        if operation == "HAS_TAG" {
            let definitions = ProjectThoughtDefinitions(raw: draft.preserved["journeyRules"], draft: draft)
            let thoughts: [Choice] = definitions.readOnly ? [] : definitions.rows.map {
                .init(id: "thought:" + $0.key, kind: .thought, label: $0.name, value: .string("thought." + $0.key + ".done"))
            }
            return thoughts + ProjectThoughtDefinitions.options(in: draft).map {
                .init(id: "tag:" + $0.tag, kind: .tag, label: $0.label, value: .string($0.tag))
            }
        }
        guard operation == "NODE_COMPLETED" else { return [] }
        let nodes = draft.chapters.flatMap(\.nodes)
        let chapterCounts = Dictionary(grouping: draft.chapters, by: \.id).mapValues(\.count)
        let eligible = Set(draft.chapters.filter { !$0.id.isEmpty && chapterCounts[$0.id] == 1 }.flatMap(\.nodes).map { Data($0.id.utf8) })
        let localCounts = Dictionary(grouping: nodes, by: \.id).mapValues(\.count)
        let saved = nodes.compactMap { node -> (ProjectEditNode, Int)? in
            guard let id = node.localMetadata["id"]?.integer, id > 0 else { return nil }; return (node, id)
        }
        let counts = Dictionary(grouping: saved, by: { $0.1 }).mapValues(\.count)
        return saved.compactMap { pair in
            let (node, id) = pair
            guard eligible.contains(Data(node.id.utf8)), !node.id.isEmpty, localCounts[node.id] == 1, counts[id] == 1 else { return nil }
            return .init(id: "node:" + String(id), kind: .node, label: node.name.isEmpty ? String(id) : node.name, value: .number(Decimal(id)))
        }
    }
    public static func currentValue(_ target: Target, in draft: ProjectEditDraft) -> ProjectEditJSON? {
        condition(draft, chapterID: target.chapterID, index: target.index)?[target.operation == "HAS_TAG" ? "value" : "nodeId"]
    }
    public static func applying(_ choice: Choice, to draft: ProjectEditDraft, target: Target) throws -> ProjectEditDraft {
        guard let ci = chapterIndex(draft, id: target.chapterID), let current = condition(draft, chapterID: target.chapterID, index: target.index),
              ProjectEditPendingMaterials.exactData(ProjectEditJSON.object(current)) == target.conditionBytes,
              current["op"]?.text == target.operation,
              choices(in: draft, operation: target.operation).contains(where: {
                  $0.id == choice.id && ProjectEditPendingMaterials.exactData($0.value) == ProjectEditPendingMaterials.exactData(choice.value)
              }), var ending = draft.chapters[ci].preserved["ending"]?.object, var rows = ending["when"]?.array else { throw ProjectEditError.invalidDraft }
        var changed = current; changed[target.operation == "HAS_TAG" ? "value" : "nodeId"] = choice.value
        if ProjectEditPendingMaterials.exactData(ProjectEditJSON.object(changed)) == target.conditionBytes { return draft }
        rows[target.index] = .object(changed); ending["when"] = .array(rows)
        var next = draft; next.chapters[ci].preserved["ending"] = .object(ending); return next
    }
}
