import Foundation

/// Current mini editor + server V2 chapter-flow contract. Evidence is not a deployment grant.
/// Rich block and beat schemas are validated by ProjectEditRichStoryContract. Unknown content
/// must never be silently flattened on replacement.
public enum ProjectEditStoryContract {
    public static let createPath = "api/topic/v2/create"
    public static let updatePath = "api/topic/v2/update"
    static let topicFields = ["configVersion", "routeMode", "routeGraphJson", "journeyRules", "journeyStory"]
    static let nodeFields = ["id", "clientNodeKey", "businessTime", "hookText", "cardHookLong", "fragmentText"]
    static let metadataFields: Set<String> = Set(["locationRequired", "who", "level", "when"]).union(ProjectEditRichStoryContract.extraFields)
    static let blockFields: Set<String> = Set(["type", "key", "content", "nodeIndex", "nodeId", "nodeKey", "url", "locationRequired", "who", "level", "when"]).union(ProjectEditRichStoryContract.extraFields)

    public static func usesV2(_ draft: ProjectEditDraft) -> Bool {
        draft.preserved["publishMode"] == .string("pro") && (draft.product == .city || draft.chapters.contains {
            $0.preserved["opening"] == .bool(true) || ($0.preserved["ending"] != nil && $0.preserved["ending"] != .null) || $0.preserved["_nativeStoredStoryFlow"] == .bool(true)
        })
    }

    /// The stripped WHITELIST body cannot select a version by itself. Use only its bound,
    /// freshly checked snapshot: legacy updates reject already-materialized chapter flows.
    public static func path(payload: [String: ProjectEditJSON], baseline: ProjectEditSnapshot?) throws -> String {
        let editing = payload["id"] != nil
        if editing { guard (payload["id"]?.integer ?? 0) > 0 else { throw ProjectEditError.invalidContract } }
        if let baseline, baseline.scope == .whitelist {
            guard baseline.topicID == payload["id"]?.integer,
                  Set(payload.keys).isSubset(of: Set(ProjectEditContract.whitelist + ["id"])) else { throw ProjectEditError.invalidContract }
            let materialized = baseline.draft.chapters.contains { $0.blocks != nil }
            return usesV2(baseline.draft) || materialized ? updatePath : "api/topic/update"
        }
        let chapters = payload["chapters"]?.array ?? []
        let story = payload["publishMode"] == .string("pro") && (payload["productType"]?.integer == 1 || chapters.contains {
            $0.object?["opening"] == .bool(true) || ($0.object?["ending"] != nil && $0.object?["ending"] != .null) || ($0.object?["schemaVersion"]?.integer == 1 && $0.object?["blocks"]?.array != nil)
        })
        if story { return editing ? updatePath : createPath }
        // Both legacy create and update explicitly reject blocks; never silently downgrade them.
        guard !chapters.contains(where: { $0.object?["blocks"] != nil || $0.object?["schemaVersion"] != nil || $0.object?["opening"] == .bool(true) }) else {
            throw ProjectEditError.invalidContract
        }
        return editing ? "api/topic/update" : "api/topic/create"
    }

    static func materializedBlocks(_ chapter: ProjectEditChapter, ordered: [ProjectEditNode]) throws -> [ProjectEditJSON] {
        guard chapter.schemaVersion == 1, chapter.required == 1 else { throw ProjectEditError.invalidDraft }
        var blocks = chapter.blocks ?? [ProjectEditBlock(kind: .text, content: chapter.description)]
        if chapter.blocks == nil { blocks[0].id = "legacy-text" }
        // Source editor keeps unreferenced legacy nodes at the end when materializing.
        let referenced = Set(blocks.filter { $0.kind == .node }.map(\.nodeID))
        for (index, node) in ordered.enumerated() where !referenced.contains(node.id) {
            var block = ProjectEditBlock(kind: .node, nodeID: node.id); block.id = "legacy-node-\(index)"; blocks.append(block)
        }
        var rows: [ProjectEditJSON] = []
        for block in blocks {
            if block.kind == .audio && block.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if block.kind == .dream, block.sourceFields?["images"]?.array?.isEmpty == true, block.sourceFields?["title"] == nil { continue }
            var row = (block.sourceFields ?? [:]).filter { $0.value != .null }
            guard Set(row.keys).isSubset(of: metadataFields) else { throw ProjectEditError.invalidDraft }
            row["key"] = .string(block.id); row["type"] = .string(block.kind.rawValue)
            switch block.kind {
            case .text:
                row["content"] = .string(block.content)
                if block.isNarrative {
                    guard let index = ordered.firstIndex(where: { $0.id == block.nodeID }) else { throw ProjectEditError.invalidDraft }
                    row["nodeIndex"] = .number(Decimal(index))
                }
            case .node:
                guard let index = ordered.firstIndex(where: { $0.id == block.nodeID }) else { throw ProjectEditError.invalidDraft }
                row["nodeIndex"] = .number(Decimal(index))
            case .image, .audio: row["url"] = .string(block.url.trimmingCharacters(in: .whitespacesAndNewlines))
            case .voice, .reveal: row["content"] = .string(block.content)
            case .mood: row["mood"] = .string(try ProjectEditRichStoryContract.normalizedMood(block.fieldText("mood")))
            case .dream, .thought, .odd: break
            }
            rows.append(.object(row))
        }
        return rows
    }

    static func projectedDescription(_ rows: [ProjectEditJSON]) -> String {
        rows.prefix { $0.object?["type"] != .string("node") }.compactMap { raw -> String? in
            guard let row = raw.object, row["type"] == .string("text"), (row["beat"]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, row["when"] == nil || row["when"] == .null else { return nil }
            return row["content"]?.text
        }.joined(separator: "\n")
    }

    /// Validates the supported V2 subset with server limits before the durable dispatch marker.
    /// Server authority, content checks, ownership and publish readiness remain server-owned.
    public static func validatePayload(_ payload: [String: ProjectEditJSON], baseline: ProjectEditSnapshot? = nil) throws {
        let selected = try path(payload: payload, baseline: baseline)
        guard selected == createPath || selected == updatePath else { return }
        if baseline?.scope == .whitelist { return }
        guard let chapters = payload["chapters"]?.array, !chapters.isEmpty else { throw ProjectEditError.invalidDraft }
        if let version = payload["configVersion"], version != .null {
            guard (version.integer ?? 0) > 0 else { throw ProjectEditError.invalidDraft }
        }
        if let mode = payload["routeMode"], mode != .null {
            guard mode == .string("LINEAR") || mode == .string("BRANCH_GRAPH") else { throw ProjectEditError.invalidDraft }
            if mode == .string("BRANCH_GRAPH") {
                guard payload["productType"]?.integer == 1, let graph = payload["routeGraphJson"]?.text,
                      !graph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectEditError.invalidDraft }
            }
        }
        var endingCount = 0, fallbackCount = 0
        var chapterIDs = Set<Int>(), nodeIDs = Set<Int>(), clientKeys = Set<String>()
        for (chapterIndex, raw) in chapters.enumerated() {
            guard let chapter = raw.object, chapter["schemaVersion"]?.integer == 1,
                  chapter["required"]?.integer == 1, let blocks = chapter["blocks"]?.array, blocks.count <= 200,
                  let nodes = chapter["nodes"]?.array else { throw ProjectEditError.invalidDraft }
            if let rawID = chapter["id"], rawID != .null {
                guard let id = rawID.integer, id > 0, chapterIDs.insert(id).inserted else { throw ProjectEditError.invalidDraft }
            }
            for rawNode in nodes {
                guard let node = rawNode.object else { throw ProjectEditError.invalidDraft }
                if let rawID = node["id"], rawID != .null {
                    guard let id = rawID.integer, id > 0, nodeIDs.insert(id).inserted else { throw ProjectEditError.invalidDraft }
                }
                if let rawKey = node["clientNodeKey"], rawKey != .null {
                    guard let key = rawKey.text, !key.isEmpty, clientKeys.insert(key).inserted else { throw ProjectEditError.invalidDraft }
                }
            }
            let opening = chapter["opening"] == .bool(true)
            if let openingValue = chapter["opening"], openingValue != .null, openingValue != .bool(true), openingValue != .bool(false) { throw ProjectEditError.invalidDraft }
            if opening { guard chapterIndex == 0, chapter["recruitEnabled"]?.integer != 1 else { throw ProjectEditError.invalidDraft } }
            if let endingValue = chapter["ending"], endingValue != .null {
                guard let ending = endingValue.object, !opening, nodes.isEmpty, chapter["recruitEnabled"]?.integer != 1,
                      Set(ending.keys).isSubset(of: ["fallback", "when"]) else { throw ProjectEditError.invalidDraft }
                endingCount += 1
                if let fallback = ending["fallback"], fallback != .bool(true), fallback != .bool(false), fallback != .null { throw ProjectEditError.invalidDraft }
                if ending["fallback"] == .bool(true) { fallbackCount += 1 }
                else {
                    guard let when = ending["when"]?.array, !when.isEmpty, when.count <= 16 else { throw ProjectEditError.invalidDraft }
                    for condition in when { try ProjectEditRichStoryContract.validateCondition(condition, ending: true) }
                }
            }
            var keys = Set<String>(), references = Set<Int>(), thoughtKeys = Set<String>()
            for rawBlock in blocks {
                guard let block = rawBlock.object, Set(block.keys).isSubset(of: blockFields.subtracting(["nodeId", "nodeKey"])),
                      let key = block["key"]?.text, matches(key, "^[A-Za-z0-9_-]{1,64}$"), keys.insert(key).inserted,
                      let kind = block["type"]?.text.flatMap(ProjectEditBlock.Kind.init(rawValue:)) else { throw ProjectEditError.invalidDraft }
                try ProjectEditRichStoryContract.validateShape(block, kind: kind)
                switch kind {
                case .node:
                    guard block["content"] == nil, block["url"] == nil,
                          let index = block["nodeIndex"]?.integer, nodes.indices.contains(index), references.insert(index).inserted,
                          let node = nodes[index].object else { throw ProjectEditError.invalidDraft }
                    if let location = block["locationRequired"], location != .bool(true), location != .bool(false) { throw ProjectEditError.invalidDraft }
                    if opening { guard block["locationRequired"] == .bool(false) else { throw ProjectEditError.invalidDraft } }
                    if block["locationRequired"] == .bool(false) {
                        guard (node["templateId"]?.integer ?? 0) > 0,
                              (node["longitude"]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              (node["latitude"]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProjectEditError.invalidDraft }
                    }
                case .text:
                    let narrative = !(block["beat"]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    guard (narrative || block["nodeIndex"] == nil), block["url"] == nil, let content = block["content"]?.text, content.utf16.count <= 5000 else { throw ProjectEditError.invalidDraft }
                    if let who = block["who"], who != .null { guard let text = who.text, text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 20 else { throw ProjectEditError.invalidDraft } }
                    if let level = block["level"], level != .null { guard let n = level.integer, (0...3).contains(n) else { throw ProjectEditError.invalidDraft } }
                    if !narrative, let when = block["when"], when != .null {
                        guard let condition = when.object, condition["op"] == .string("HAS_TAG"),
                              let value = condition["value"]?.text, matches(value, "^(tag\\.[a-z][a-z0-9_]{0,47}|thought\\.[a-z][a-z0-9_]{0,47}\\.done)$") else { throw ProjectEditError.invalidDraft }
                    }
                case .image, .audio:
                    guard block["content"] == nil, block["nodeIndex"] == nil, let url = block["url"]?.text,
                          !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, url.utf16.count <= 500 else { throw ProjectEditError.invalidDraft }
                case .thought:
                    guard thoughtKeys.insert(ProjectEditRichStoryContract.trim(block["thoughtKey"])).inserted else { throw ProjectEditError.invalidDraft }
                case .dream, .mood, .voice, .odd, .reveal: break
                }
            }
            try ProjectEditRichStoryContract.validateNarrative(blocks, nodeCount: nodes.count)
            guard references.count == nodes.count, projectedDescription(blocks).utf16.count <= 8000,
                  try JSONEncoder().encode(blocks).count <= 64 * 1024 else { throw ProjectEditError.invalidDraft }
        }
        guard endingCount == 0 || fallbackCount == 1 else { throw ProjectEditError.invalidDraft }
    }

    /// edit-detail also synthesizes legacy text/node blocks. Those are safe to omit only
    /// when the server explicitly reports no stored flow and every value matches the legacy projection.
    static func isLegacyProjection(_ chapter: ProjectEditChapter) -> Bool {
        guard chapter.preserved["_nativeStoredStoryFlow"] == .bool(false), let blocks = chapter.blocks,
              blocks.count == chapter.nodes.count + 1, let first = blocks.first,
              first.kind == .text, first.content == chapter.description,
              blocks.allSatisfy({ $0.sourceFields == nil || $0.sourceFields?.isEmpty == true }) else { return false }
        return zip(blocks.dropFirst(), chapter.nodes).allSatisfy { block, node in block.kind == .node && block.nodeID == node.id }
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }

    /// Uses the existing edit-detail response, never a guessed v2 detail endpoint.
    static func restoreMetadata(_ draft: inout ProjectEditDraft, body: [String: ProjectEditJSON], topic: [String: ProjectEditJSON]) throws {
        for key in topicFields { if let value = topic[key], value != .null { draft.preserved[key] = value } }
        for key in ["journeyRules", "journeyStory"] {
            if let value = body[key] ?? topic[key + "Json"], value != .null { draft.preserved[key] = value }
        }
        if let version = draft.preserved["configVersion"], version != .null, (version.integer ?? 0) <= 0 { throw ProjectEditError.invalidContract }
        if let collaborators = body["collaboratorIds"] {
            guard let rows = collaborators.array else { throw ProjectEditError.invalidContract }
            draft.collaboratorIDs = try rows.map { guard let id = $0.integer, id > 0 else { throw ProjectEditError.invalidContract }; return id }
        }
        let story: [String: ProjectEditJSON]
        if let raw = draft.preserved["journeyStory"], raw != .null, raw != .string("") {
            guard let string = raw.text, let parsed = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: Data(string.utf8)) else { throw ProjectEditError.invalidContract }
            story = parsed
        } else { story = [:] }
        if let opening = body["openingChapterId"] ?? story["openingChapterId"], opening != .null {
            guard let id = opening.integer, id > 0, let index = draft.chapters.firstIndex(where: { $0.preserved["id"]?.integer == id }) else { throw ProjectEditError.invalidContract }
            draft.chapters[index].preserved["opening"] = .bool(true)
        }
        if let rawEndings = story["ending"]?.object?["endings"] {
            guard let endings = rawEndings.array else { throw ProjectEditError.invalidContract }
            try ProjectEditRichStoryContract.attachEndings(endings, draft: &draft)
        }
    }
}

/// An immediate review acknowledgment is distinct from approval, publication, or a later receipt.
public struct ProjectEditBundleAcknowledgment: Equatable, Codable {
    public let topicID: Int
    public let auditTaskID: Int?
    public let reviewState: String
    public let published: Bool
    public let bundledTemplateIDs: [Int]
    public init(from decoder: Decoder) throws {
        self = try Self.decode(try ProjectEditJSON(from: decoder), expectedTopicID: nil)
    }
    public func encode(to encoder: Encoder) throws {
        var body: [String: ProjectEditJSON] = ["topicId": .number(Decimal(topicID)), "reviewState": .string(reviewState),
            "published": .bool(published), "bundledTemplateIds": .array(bundledTemplateIDs.map { .number(Decimal($0)) })]
        body["auditTaskId"] = auditTaskID.map { .number(Decimal($0)) } ?? .null
        try ProjectEditJSON.object(body).encode(to: encoder)
    }
    private init(topicID: Int, auditTaskID: Int?, reviewState: String, published: Bool, bundledTemplateIDs: [Int]) {
        self.topicID = topicID; self.auditTaskID = auditTaskID; self.reviewState = reviewState
        self.published = published; self.bundledTemplateIDs = bundledTemplateIDs
    }
    public static func decode(_ value: ProjectEditJSON?, expectedTopicID: Int?) throws -> Self {
        guard let body = value?.object, let topic = body["topicId"]?.integer, topic > 0,
              expectedTopicID == nil || expectedTopicID == topic,
              let state = body["reviewState"]?.text, ["PENDING", "ESCALATED", "DRAFT", "NOT_REQUIRED"].contains(state),
              case .bool(let published)? = body["published"], let rawIDs = body["bundledTemplateIds"]?.array else { throw ProjectEditError.invalidContract }
        let audit = body["auditTaskId"]?.integer
        if state == "PENDING" || state == "ESCALATED" { guard let audit, audit > 0 else { throw ProjectEditError.invalidContract } }
        else if let raw = body["auditTaskId"], raw != .null { guard let audit, audit > 0 else { throw ProjectEditError.invalidContract } }
        if state == "DRAFT", published { throw ProjectEditError.invalidContract }
        let ids = try rawIDs.map { raw -> Int in guard let id = raw.integer, id > 0 else { throw ProjectEditError.invalidContract }; return id }
        guard Set(ids).count == ids.count else { throw ProjectEditError.invalidContract }
        return .init(topicID: topic, auditTaskID: audit, reviewState: state, published: published, bundledTemplateIDs: ids)
    }
}
