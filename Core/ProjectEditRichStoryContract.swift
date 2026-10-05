import Foundation

public enum ProjectEditNarrativeBeat: String, Codable, CaseIterable, Identifiable, Hashable {
    case brief, route, enter, outcome, deliver, unlock, revisit
    public var id: String { rawValue }
    public var fields: [String] {
        switch self {
        case .brief: return ["question", "body", "carry"]
        case .route: return ["walk", "todo"]
        case .enter: return ["opener", "aside", "q", "a"]
        case .outcome: return ["title", "line", "lineIfFail", "fact", "open"]
        case .deliver: return ["reward", "line"]
        case .unlock: return ["hook"]
        case .revisit: return ["change"]
        }
    }
    public var afterNode: Bool { [.outcome, .deliver, .revisit].contains(self) }
    public var supportsNPC: Bool { self == .enter || self == .outcome }
}

public extension ProjectEditBlock {
    var isNarrative: Bool { kind == .text && !(sourceFields?["beat"]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func fieldText(_ key: String) -> String {
        if let text = sourceFields?[key]?.text { return text }
        if case .number(let value)? = sourceFields?[key] { return NSDecimalNumber(decimal: value).stringValue }
        return ""
    }
    mutating func setField(_ key: String, _ value: ProjectEditJSON?) {
        var fields = sourceFields ?? [:]; fields[key] = value; sourceFields = fields.isEmpty ? nil : fields
    }
    mutating func setIntegerField(_ key: String, _ text: String) {
        if text.isEmpty { setField(key, nil) }
        else if let value = Int(text), String(value) == text { setField(key, .number(Decimal(value))) }
        else { setField(key, .string(text)) }
    }
    mutating func selectBeat(_ beat: ProjectEditNarrativeBeat?) {
        for key in ["beat", "field", "qid", "npcId", "claimLater", "when"] { setField(key, nil) }
        if let beat { setField("beat", .string(beat.rawValue)); setField("field", .string(beat.fields[0])) }
        else { nodeID = "" }
    }
    mutating func selectNarrativeField(_ field: String) {
        guard let beat = ProjectEditNarrativeBeat(rawValue: fieldText("beat")), beat.fields.contains(field) else { return }
        setField("field", .string(field))
        if beat != .enter || !["q", "a"].contains(field) { setField("qid", nil) }
        if !["brief.carry", "outcome.fact", "revisit.change"].contains(beat.rawValue + "." + field) { setField("when", nil) }
    }
    var dreamImages: [[String: ProjectEditJSON]] { sourceFields?["images"]?.array?.compactMap(\.object) ?? [] }
    mutating func setDreamImage(index: Int, field: String, value: String) {
        var images = dreamImages; guard images.indices.contains(index), ["url", "line"].contains(field) else { return }
        images[index][field] = .string(value); setField("images", .array(images.map(ProjectEditJSON.object)))
    }
    mutating func appendDreamImage() {
        var images = dreamImages; guard images.count < 6 else { return }; images.append(["url": .string(""), "line": .string("")])
        setField("images", .array(images.map(ProjectEditJSON.object)))
    }
    mutating func removeDreamImage(index: Int) {
        var images = dreamImages; guard images.indices.contains(index) else { return }; images.remove(at: index)
        setField("images", .array(images.map(ProjectEditJSON.object)))
    }
}

/// Derived contract shapes; does not execute narrative rules, resolve authority or contact a backend.
public enum ProjectEditRichStoryContract {
    public static let richKinds: [ProjectEditBlock.Kind] = [.dream, .mood, .thought, .voice, .odd, .reveal]
    public static let voices = ["规矩", "窗外", "心", "精密", "咔哒"]
    public static let moods = ["DEFAULT", "BLUE", "RED", "YELLOW", "WHITE"]
    public static let comparisonOps = ["EQ", "NE", "GT", "GTE", "LT", "LTE"]
    public static let conditionOps = ["HAS_TAG", "NODE_COMPLETED"] + comparisonOps
    static let extraFields: Set<String> = ["images", "title", "mood", "thoughtKey", "beat", "field", "qid", "npcId", "claimLater"]
    public static func defaultBlock(_ kind: ProjectEditBlock.Kind) -> ProjectEditBlock {
        var block = ProjectEditBlock(kind: kind)
        switch kind {
        case .dream: block.setField("images", .array([]))
        case .mood: block.setField("mood", .string("DEFAULT"))
        case .voice: block.setField("who", .string(voices[0]))
        case .odd: block.setField("level", .number(0))
        default: break
        }
        return block
    }
    static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    static func nonnull(_ value: ProjectEditJSON?) -> ProjectEditJSON? { value == .null ? nil : value }
    static func trim(_ value: ProjectEditJSON?) -> String { value?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    public static func normalizedMood(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if moods.contains(name) { return name }
        let aliases = ["NIGHT": "BLUE", "ARCHIVE": "YELLOW", "NEON": "RED", "MOSS": "DEFAULT"]
        guard let value = aliases[name] else { throw ProjectEditError.invalidDraft }; return value
    }
    static func validateShape(_ block: [String: ProjectEditJSON], kind: ProjectEditBlock.Kind) throws {
        let allowed: Set<String>
        switch kind {
        case .text: allowed = ["type", "key", "content", "who", "level", "when", "beat", "field", "qid", "npcId", "claimLater", "nodeIndex"]
        case .node: allowed = ["type", "key", "nodeIndex", "locationRequired"]
        case .image, .audio: allowed = ["type", "key", "url"]
        case .dream: allowed = ["type", "key", "images", "title"]
        case .mood: allowed = ["type", "key", "mood"]
        case .thought: allowed = ["type", "key", "thoughtKey"]
        case .voice: allowed = ["type", "key", "who", "content", "when"]
        case .odd: allowed = ["type", "key", "level"]
        case .reveal: allowed = ["type", "key", "who", "content"]
        }
        guard Set(block.keys).isSubset(of: allowed) else { throw ProjectEditError.invalidDraft }
        switch kind {
        case .dream:
            guard let images = block["images"]?.array, (1...6).contains(images.count) else { throw ProjectEditError.invalidDraft }
            if let raw = nonnull(block["title"]) { guard raw.text != nil, trim(raw).utf16.count <= 20 else { throw ProjectEditError.invalidDraft } }
            for raw in images {
                guard let image = raw.object, Set(image.keys).isSubset(of: ["url", "line"]), let url = image["url"]?.text,
                      !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, url.utf16.count <= 500 else { throw ProjectEditError.invalidDraft }
                if let line = nonnull(image["line"]) { guard let text = line.text, text.utf16.count <= 80 else { throw ProjectEditError.invalidDraft } }
            }
        case .mood: guard let value = block["mood"]?.text else { throw ProjectEditError.invalidDraft }; _ = try normalizedMood(value)
        case .thought: guard matches(trim(block["thoughtKey"]), "^[a-z][a-z0-9_]{0,31}$") else { throw ProjectEditError.invalidDraft }
        case .voice:
            guard let who = block["who"]?.text, voices.contains(who), block["content"]?.text != nil,
                  !trim(block["content"]).isEmpty, trim(block["content"]).utf16.count <= 200 else { throw ProjectEditError.invalidDraft }
            if let when = nonnull(block["when"]) { try validatePlainCondition(when) }
        case .odd: guard let level = block["level"]?.integer, (0...3).contains(level) else { throw ProjectEditError.invalidDraft }
        case .reveal:
            guard block["content"]?.text != nil, !trim(block["content"]).isEmpty, trim(block["content"]).utf16.count <= 500 else { throw ProjectEditError.invalidDraft }
            if let who = nonnull(block["who"]) { guard who.text != nil, trim(who).utf16.count <= 20 else { throw ProjectEditError.invalidDraft } }
        default: break
        }
    }
    static func validatePlainCondition(_ raw: ProjectEditJSON) throws {
        guard let value = raw.object, value["op"] == .string("HAS_TAG"), let tag = value["value"]?.text,
              matches(tag, "^(tag\\.[a-z][a-z0-9_]{0,47}|thought\\.[a-z][a-z0-9_]{0,47}\\.done)$") else { throw ProjectEditError.invalidDraft }
    }
    /// Narrative conditions and ending conditions have distinct HAS_TAG domains in current source.
    public static func validateCondition(_ raw: ProjectEditJSON, ending: Bool = false) throws {
        guard let value = raw.object, let op = value["op"]?.text,
              Set(value.keys).isSubset(of: ["op", "var", "value", "nodeId"]) else { throw ProjectEditError.invalidDraft }
        if op == "NODE_COMPLETED" { guard (value["nodeId"]?.integer ?? 0) > 0 else { throw ProjectEditError.invalidDraft }; return }
        if op == "HAS_TAG" {
            let pattern = ending ? "^(tag\\.[a-z][a-z0-9_]{0,47}|thought\\.[a-z][a-z0-9_]{0,47}\\.done)$" : "^tag\\.[a-z][a-z0-9_]{0,47}$"
            guard matches(trim(value["value"]), pattern) else { throw ProjectEditError.invalidDraft }; return
        }
        guard comparisonOps.contains(op), let number = value["value"]?.integer, (-99...99).contains(number) else { throw ProjectEditError.invalidDraft }
        let variable = trim(value["var"])
        let valid = ["sys.hp", "sys.luck", "sys.exhausted"].contains(variable)
            || matches(variable, "^(clue|relation|counter)\\.[a-z][a-z0-9_]{0,47}$")
            || matches(variable, "^sys\\.asked\\.[1-9][0-9]*\\.[A-Za-z0-9_-]{1,32}$")
            || matches(variable, "^sys\\.(mistakes|outcome|passed)\\.[1-9][0-9]*$")
        guard valid else { throw ProjectEditError.invalidDraft }
    }
    static func validateNarrative(_ blocks: [ProjectEditJSON], nodeCount: Int) throws {
        var positions: [Int: Int] = [:]
        for (index, raw) in blocks.enumerated() {
            guard let row = raw.object else { throw ProjectEditError.invalidDraft }
            if row["type"] == .string("node"), let node = row["nodeIndex"]?.integer {
                guard positions[node] == nil else { throw ProjectEditError.invalidDraft }; positions[node] = index
            }
        }
        var slots = Set<String>(), questions: [Int: Set<String>] = [:], answers: [Int: Set<String>] = [:]
        var npcs: [String: Int] = [:], counts: [String: Int] = [:], delivered = Set<Int>(), rewarded = Set<Int>()
        let repeating: Set<String> = ["brief.carry", "outcome.fact", "revisit.change", "enter.q", "enter.a"]
        let conditional: Set<String> = ["brief.carry", "outcome.fact", "revisit.change"]
        for (position, raw) in blocks.enumerated() {
            guard let row = raw.object else { throw ProjectEditError.invalidDraft }
            let beatText = trim(row["beat"])
            if beatText.isEmpty {
                guard ["field", "qid", "npcId", "claimLater"].allSatisfy({ nonnull(row[$0]) == nil }) else { throw ProjectEditError.invalidDraft }
                continue
            }
            guard row["type"] == .string("text"), let beat = ProjectEditNarrativeBeat(rawValue: beatText),
                  let node = row["nodeIndex"]?.integer, (0..<nodeCount).contains(node), let nodePosition = positions[node],
                  beat.afterNode ? position > nodePosition : position < nodePosition,
                  row["content"]?.text != nil, !trim(row["content"]).isEmpty, trim(row["content"]).utf16.count <= 200 else { throw ProjectEditError.invalidDraft }
            let field = trim(row["field"]), slot = beat.rawValue + "." + field, scoped = "\(node):\(slot)"
            guard beat.fields.contains(field) else { throw ProjectEditError.invalidDraft }
            if !repeating.contains(slot) { guard slots.insert(scoped).inserted else { throw ProjectEditError.invalidDraft } }
            let qa = beat == .enter && (field == "q" || field == "a")
            if qa {
                let qid = trim(row["qid"]); guard matches(qid, "^[A-Za-z0-9_-]{1,32}$") else { throw ProjectEditError.invalidDraft }
                if field == "q" { guard questions[node, default: []].insert(qid).inserted else { throw ProjectEditError.invalidDraft } }
                else { guard answers[node, default: []].insert(qid).inserted else { throw ProjectEditError.invalidDraft } }
            } else if nonnull(row["qid"]) != nil { throw ProjectEditError.invalidDraft }
            if let rawNPC = nonnull(row["npcId"]) {
                guard beat.supportsNPC, let npc = rawNPC.integer, npc > 0 else { throw ProjectEditError.invalidDraft }
                let key = "\(node):\(beat.rawValue)"; guard npcs[key] == nil || npcs[key] == npc else { throw ProjectEditError.invalidDraft }; npcs[key] = npc
            }
            if let when = nonnull(row["when"]) { guard conditional.contains(slot) else { throw ProjectEditError.invalidDraft }; try validateCondition(when) }
            if let claim = nonnull(row["claimLater"]) { guard beat == .deliver, claim == .bool(true) || claim == .bool(false) else { throw ProjectEditError.invalidDraft } }
            counts[scoped, default: 0] += 1
            let limit = slot == "brief.carry" || slot == "outcome.fact" ? 8 : slot == "revisit.change" ? 6 : Int.max
            guard counts[scoped, default: 0] <= limit, questions[node, default: []].count <= 6 else { throw ProjectEditError.invalidDraft }
            if beat == .deliver { delivered.insert(node); if field == "reward" { rewarded.insert(node) } }
        }
        for node in Set(questions.keys).union(answers.keys) { guard questions[node, default: []] == answers[node, default: []] else { throw ProjectEditError.invalidDraft } }
        guard delivered.isSubset(of: rewarded) else { throw ProjectEditError.invalidDraft }
    }

    /// Legacy non-chapter ending rows become deterministic local chapters, matching current mini migration.
    static func attachEndings(_ rows: [ProjectEditJSON], draft: inout ProjectEditDraft) throws {
        var assigned = Set<Int>()
        for (index, raw) in rows.enumerated() {
            guard let row = raw.object, Set(row.keys).isSubset(of: ["code", "title", "summary", "fallback", "when", "chapterId"]) else { throw ProjectEditError.invalidContract }
            var fields: [String: ProjectEditJSON] = [:]
            for key in ["fallback", "when"] { if let value = row[key] { fields[key] = value } }
            if let id = row["chapterId"]?.integer, let ci = draft.chapters.firstIndex(where: { $0.preserved["id"]?.integer == id }) {
                guard assigned.insert(ci).inserted else { throw ProjectEditError.invalidContract }; draft.chapters[ci].preserved["ending"] = .object(fields)
            } else {
                var chapter = ProjectEditChapter(); chapter.id = "legacy-ending-\(index)"
                chapter.name = row["title"]?.text ?? ""; chapter.description = row["summary"]?.text ?? ""
                chapter.blocks = []
                if !chapter.description.isEmpty { var block = ProjectEditBlock(kind: .text, content: chapter.description); block.id = "legacy-ending-\(index)-summary"; chapter.blocks = [block] }
                chapter.preserved["ending"] = .object(fields); draft.chapters.append(chapter)
            }
        }
    }
    static func journeyStoryWithoutStandaloneEndingList(_ raw: ProjectEditJSON) throws -> ProjectEditJSON {
        guard let text = raw.text else { if raw == .null { return raw }; throw ProjectEditError.invalidDraft }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return raw }
        var root = try JSONDecoder().decode([String: ProjectEditJSON].self, from: Data(text.utf8))
        guard let ending = root["ending"]?.object, Set(ending.keys) == ["endings"] else { return raw }
        root.removeValue(forKey: "ending")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return .string(String(decoding: try encoder.encode(root), as: UTF8.self))
    }
}
