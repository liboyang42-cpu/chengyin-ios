import Foundation

/// Immutable, local author-content projection. No live route, condition, variable,
/// gameplay, media, result or reward evaluator is involved.
public struct ProjectDraftStoryPreview {
    public enum Reason: String { case identity, limit, branchRoute, unsupportedRoute }
    public enum Role: String { case chapter, opening, ending, unsupported }
    public enum Kind: String { case text, voice, narrative, node, image, audio, album, thought, mood, odd, reveal, unsupported }
    public struct Row: Identifiable {
        public let id: Int
        public let kind: Kind
        public let title: String
        public let text: String
        public let details: [String]
        public let conditional: Bool
        public let unsupported: Bool
        public let emptyMediaReference: Bool
    }
    public struct Chapter: Identifiable {
        public let id: Data
        public let title: String
        public let role: Role
        public let rows: [Row]
        public let unsupported: Bool
        public let unplacedNodeCount: Int
    }
    public let title: String
    public let subtitle: String
    public let excludedPendingCount: Int
    public private(set) var chapters: [Chapter] = []
    public private(set) var reason: Reason?
    private var sourceBytes: Data?
    public init(draft: ProjectEditDraft) {
        title = draft.name; subtitle = draft.subtitle
        excludedPendingCount = (draft.pendingMaterials ?? []).count
        guard draft.chapters.count <= 128, draft.chapters.flatMap(\.nodes).count <= 512,
              draft.chapters.allSatisfy({ ($0.blocks?.count ?? 0) <= 200 }),
              draft.chapters.reduce(0, { $0 + ($1.blocks?.count ?? 0) }) <= 4096,
              let bytes = ProjectEditPendingMaterials.exactData(draft), bytes.count <= 1024 * 1024 else { reason = .limit; return }
        sourceBytes = bytes
        let chapterIDs = draft.chapters.map(\.id)
        let nodeIDs = draft.chapters.flatMap(\.nodes).map(\.id) + (draft.pendingMaterials ?? []).map(\.id)
        // Child authoring models still use String identity. Fail closed on exact
        // duplicates and Unicode-canonical aliases; never pick the first row.
        guard Self.unique(chapterIDs), Self.unique(nodeIDs), draft.chapters.allSatisfy({ Self.unique(($0.blocks ?? []).map(\.id)) }) else {
            reason = .identity; return
        }
        if let mode = draft.preserved["routeMode"], mode != .null {
            if mode == .string("BRANCH_GRAPH") { reason = .branchRoute; return }
            guard mode == .string("LINEAR") else { reason = .unsupportedRoute; return }
        }
        let thoughts = Self.thoughtLabels(draft.preserved["journeyRules"])
        chapters = draft.chapters.map { chapter in
            let role = Self.role(chapter)
            guard chapter.schemaVersion == 1, chapter.required == 1, role != .unsupported else {
                return .init(id: Data(chapter.id.utf8), title: chapter.name, role: role, rows: [], unsupported: true, unplacedNodeCount: 0)
            }
            var rows: [Row] = []
            var unplaced = 0
            if let blocks = chapter.blocks {
                for block in blocks { rows += Self.rows(block, in: chapter, thoughts: thoughts, start: rows.count) }
                // Explicit block order is not rewritten to invent a route for
                // placed nodes that have no story marker in this local draft.
                let referenced = Set(blocks.filter { $0.kind == .node }.map { Data($0.nodeID.utf8) })
                unplaced = chapter.nodes.filter { !referenced.contains(Data($0.id.utf8)) }.count
            } else {
                if !chapter.description.isEmpty { rows.append(Self.row(rows.count, .text, text: chapter.description)) }
                for node in chapter.nodes { rows.append(Self.row(rows.count, .node, title: node.name, text: node.description)) }
            }
            return .init(id: Data(chapter.id.utf8), title: chapter.name, role: role, rows: rows, unsupported: false, unplacedNodeCount: unplaced)
        }
    }
    public func isCurrent(in draft: ProjectEditDraft) -> Bool {
        sourceBytes != nil && ProjectEditPendingMaterials.exactData(draft) == sourceBytes
    }
    private static func unique(_ ids: [String]) -> Bool { ids.allSatisfy({ !$0.isEmpty }) && Set(ids).count == ids.count }
    private static func role(_ chapter: ProjectEditChapter) -> Role {
        let opening = chapter.preserved["opening"]
        if let opening, opening != .null, opening != .bool(true), opening != .bool(false) { return .unsupported }
        let ending = chapter.preserved["ending"]
        if let ending, ending != .null, ending.object == nil { return .unsupported }
        if opening == .bool(true) { return ending == nil || ending == .null ? .opening : .unsupported }
        return ending?.object == nil ? .chapter : .ending
    }
    private static func row(_ id: Int, _ kind: Kind, title: String = "", text: String = "", details: [String] = [],
                            conditional: Bool = false, unsupported: Bool = false, emptyMediaReference: Bool = false) -> Row {
        .init(id: id, kind: kind, title: title, text: text, details: details, conditional: conditional,
              unsupported: unsupported, emptyMediaReference: emptyMediaReference)
    }
    private static func rows(_ block: ProjectEditBlock, in chapter: ProjectEditChapter,
                             thoughts: [String: (String, String, String)], start: Int) -> [Row] {
        let condition = block.sourceFields?["when"]
        let conditional = condition != nil && condition != .null
        let badCondition = conditional && condition?.object == nil
        let known = Set(ProjectEditStoryContract.metadataFields)
        let unknown = !(Set((block.sourceFields ?? [:]).keys).isSubset(of: known))
        let unsupported = badCondition || unknown
        switch block.kind {
        case .text:
            if block.isNarrative {
                let target = chapter.nodes.first { $0.id.utf8.elementsEqual(block.nodeID.utf8) }
                return [row(start, .narrative, title: target?.name ?? "", text: block.content,
                            conditional: conditional, unsupported: unsupported || target == nil)]
            }
            return [row(start, .text, text: block.content, conditional: conditional, unsupported: unsupported)]
        case .voice:
            return [row(start, .voice, title: block.fieldText("who"), text: block.content, conditional: conditional, unsupported: unsupported)]
        case .reveal:
            return [row(start, .reveal, text: block.content, conditional: conditional, unsupported: unsupported)]
        case .node:
            guard let node = chapter.nodes.first(where: { $0.id.utf8.elementsEqual(block.nodeID.utf8) }) else {
                return [row(start, .unsupported, conditional: conditional, unsupported: true)]
            }
            return [row(start, .node, title: node.name, text: node.description, conditional: conditional, unsupported: unsupported)]
        case .image, .audio:
            return [row(start, block.kind == .image ? .image : .audio, conditional: conditional,
                        unsupported: unsupported, emptyMediaReference: block.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)]
        case .dream:
            guard let values = block.sourceFields?["images"]?.array, values.count <= 6 else { return [row(start, .album, conditional: conditional, unsupported: true)] }
            var captions: [String] = [], bad = unsupported
            for value in values {
                guard let object = value.object else { captions.append(""); bad = true; continue }
                if let line = object["line"] {
                    if let text = line.text { captions.append(text) } else { captions.append(""); bad = true }
                } else { captions.append("") }
                if let url = object["url"], url.text == nil { bad = true }
                if !Set(object.keys).isSubset(of: ["url", "line"]) { bad = true }
            }
            return [row(start, .album, title: block.fieldText("title"), details: captions,
                        conditional: conditional, unsupported: bad)]
        case .thought:
            let key = block.fieldText("thoughtKey")
            guard let thought = thoughts[key], thought.0.utf8.elementsEqual(key.utf8) else {
                return [row(start, .thought, conditional: conditional, unsupported: true)]
            }
            return [row(start, .thought, title: thought.1, text: thought.2, conditional: conditional, unsupported: unsupported)]
        case .mood:
            let mood = block.fieldText("mood")
            let valid = (try? ProjectEditRichStoryContract.normalizedMood(mood)) != nil
            return [row(start, .mood, title: mood, conditional: conditional, unsupported: unsupported || !valid)]
        case .odd:
            return [row(start, .odd, conditional: conditional, unsupported: unsupported)]
        }
    }
    private static func thoughtLabels(_ raw: ProjectEditJSON?) -> [String: (String, String, String)] {
        guard let text = raw?.text, text.utf8.count <= 16 * 1024,
              let root = try? ApprovedTopicReleaseWire.envelope(Data(text.utf8)), let values = root["thoughts"]?.array,
              values.count <= 8 else { return [:] }
        var labels: [String: (String, String, String)] = [:]
        for value in values {
            guard let object = value.object, let key = object["key"]?.text, !key.isEmpty,
                  let name = object["name"]?.text, labels[key] == nil,
                  object["desc"] == nil || object["desc"]?.text != nil else { return [:] }
            labels[key] = (key, name, object["desc"]?.text ?? "")
        }
        return labels
    }
}
