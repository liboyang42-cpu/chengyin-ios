import Foundation

/// A bounded, existing-graph projection. The only writable token is one existing
/// edge.toNodeId. Source templates are inspected in place and never copied.
public struct ProjectNodeRouteMapping {
    public enum Reason: String, Error { case unsupported, identity, outcomes, ambiguous, cycle, reachability, fallback, noEdges, changed }
    public struct Target: Identifiable {
        public let id: Int
        public let label: String
        public let reason: Reason?
    }
    public struct Row: Identifiable {
        public let id: String
        public let label: String
        public let triggerType: String
        public let outcomeCode: String
        public let targetID: Int
        public let reason: Reason?
        fileprivate let index: Int
    }
    public private(set) var reason: Reason?
    public private(set) var rows: [Row] = []
    private var nodes: [ProjectEditNode] = []
    private var graph: [String: ProjectEditJSON] = [:]
    private var edges: [[String: ProjectEditJSON]] = []
    private var original = ""
    private var draftBytes: Data?

    public init(draft: ProjectEditDraft, chapterID: String, nodeID: String) {
        do {
            guard draft.product == .city, ProjectEditStoryContract.usesV2(draft),
                  draft.preserved["routeMode"] == .string("BRANCH_GRAPH"),
                  let raw = draft.preserved["routeGraphJson"]?.text, !raw.isEmpty, raw.utf8.count <= 262_144 else { throw Reason.unsupported }
            nodes = draft.chapters.flatMap(\.nodes)
            guard nodes.count <= 128 else { throw Reason.unsupported }
            guard !nodes.isEmpty,
                  draft.chapters.allSatisfy({ !$0.id.isEmpty }), Set(draft.chapters.map(\.id)).count == draft.chapters.count,
                  nodes.allSatisfy({ !$0.id.isEmpty }), Set(nodes.map(\.id)).count == nodes.count,
                  let chapter = draft.chapters.first(where: { $0.id.utf8.elementsEqual(chapterID.utf8) }),
                  let source = chapter.nodes.first(where: { $0.id.utf8.elementsEqual(nodeID.utf8) }) else { throw Reason.identity }
            let ids = try nodes.map { node -> Int in
                guard let id = node.localMetadata["id"]?.integer, id > 0 else { throw Reason.identity }; return id
            }
            guard Set(ids).count == ids.count, let sourceID = source.localMetadata["id"]?.integer else { throw Reason.identity }
            original = raw; graph = try Self.graphDocument(raw)
            try Self.validate(graph, nodes: nodes)
            guard let rawEdges = graph["edges"]?.array else { throw Reason.unsupported }
            edges = try rawEdges.map { guard let value = $0.object else { throw Reason.unsupported }; return value }
            let own = edges.indices.filter { Self.nodeID(edges[$0]["fromNodeId"]) == sourceID }
            guard !own.isEmpty else { reason = .noEdges; return }
            let declarations = try Self.outcomes(source)
            for index in own {
                let edge = edges[index], trigger = edge["trigger"]!.object!
                let type = trigger["type"]!.text!, code = trigger["outcomeCode"]!.text!
                let matches = own.filter {
                    guard let item = edges[$0]["trigger"]?.object, let otherType = item["type"]?.text, let otherCode = item["outcomeCode"]?.text else { return false }
                    return Self.exact(otherType, type) && Self.exact(otherCode, code)
                }
                rows.append(.init(id: edge["id"]!.text!, label: declarations.first(where: { Self.exact($0.type, type) && Self.exact($0.code, code) })!.label,
                    triggerType: type, outcomeCode: code, targetID: Self.nodeID(edge["toNodeId"])!, reason: matches.count == 1 ? nil : .ambiguous, index: index))
            }
            draftBytes = ProjectEditPendingMaterials.exactData(draft)
            guard draftBytes != nil else { throw Reason.unsupported }
        } catch let failure as Reason { reason = failure; rows = [] }
        catch { reason = .unsupported; rows = [] }
    }

    /// Each disabled destination has a concrete safety reason. Nothing is repaired
    /// or synthesized to make a destination available.
    public func targets(for edgeID: String) -> [Target] {
        guard reason == nil, let row = rows.first(where: { $0.id.utf8.elementsEqual(edgeID.utf8) }), row.reason == nil else { return [] }
        return nodes.compactMap { node in
            guard let id = node.localMetadata["id"]?.integer else { return nil }
            let failure: Reason?
            do { try Self.validate(replacing(row, with: id), nodes: nodes); failure = nil }
            catch let reason as Reason { failure = reason }
            catch { failure = .unsupported }
            return .init(id: id, label: node.name.isEmpty ? String(id) : node.name, reason: failure)
        }
    }
    public func applying(edgeID: String, targetID: Int, to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard reason == nil, draftBytes != nil, ProjectEditPendingMaterials.exactData(draft) == draftBytes,
              let row = rows.first(where: { $0.id.utf8.elementsEqual(edgeID.utf8) }), row.reason == nil,
              nodes.contains(where: { $0.localMetadata["id"]?.integer == targetID }) else { throw Reason.changed }
        if row.targetID == targetID { return draft } // Exact raw bytes, revision and storage stay untouched.
        let expected = replacing(row, with: targetID)
        try Self.validate(expected, nodes: nodes)
        var scanner = TokenScanner(bytes: Array(original.utf8), wanted: ["edges", String(row.index), "toNodeId"])
        try scanner.value(path: [])
        guard let range = scanner.found else { throw Reason.unsupported }
        let token = edges[row.index]["toNodeId"]?.text == nil ? String(targetID) : "\"\(targetID)\""
        var bytes = Array(original.utf8); bytes.replaceSubrange(range, with: token.utf8)
        guard let raw = String(bytes: bytes, encoding: .utf8),
              ProjectEditPendingMaterials.exactData(try Self.graphDocument(raw)) == ProjectEditPendingMaterials.exactData(expected) else { throw Reason.unsupported }
        var next = draft; next.preserved["routeGraphJson"] = .string(raw); return next
    }
    private func replacing(_ row: Row, with id: Int) -> [String: ProjectEditJSON] {
        var changed = edges[row.index]
        changed["toNodeId"] = changed["toNodeId"]?.text == nil ? .number(Decimal(id)) : .string(String(id))
        var rawEdges = graph["edges"]!.array!; rawEdges[row.index] = .object(changed)
        var next = graph; next["edges"] = .array(rawEdges); return next
    }
    /// ContentDraftJSON retains decoded object keys as exact UTF-8 Data. Reject
    /// canonically equivalent distinct keys before Foundation's String-keyed map
    /// could collapse them. Preserve the unsupported raw document without edits.
    private static func graphDocument(_ raw: String) throws -> [String: ProjectEditJSON] {
        guard raw.utf8.count <= 262_144 else { throw Reason.unsupported }
        func checkKeys(_ value: ContentDraftJSON) throws {
            switch value {
            case .object(let fields):
                var seen = Set<String>()
                for (bytes, child) in fields {
                    guard let key = String(data: bytes, encoding: .utf8), seen.insert(key).inserted else { throw Reason.unsupported }
                    try checkKeys(child)
                }
            case .array(let values): for child in values { try checkKeys(child) }
            default: break
            }
        }
        // The caller already bounds the raw graph to 256 KiB. The lossless parser
        // itself bounds depth/exponents; the shared envelope then applies its
        // stricter resource preflight and full Foundation decoding.
        try checkKeys(ContentDraftJSON.parse(raw))
        return try ApprovedTopicReleaseWire.envelope(Data(raw.utf8))
    }
    private static func nodeID(_ value: ProjectEditJSON?) -> Int? {
        if let number = value?.integer, number > 0 { return number }
        guard let text = value?.text, !text.isEmpty, text.first != "0", text.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(text), number > 0 else { return nil }
        return number
    }
    private static func exact(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.elementsEqual(rhs.utf8) }
    private static func keys(_ value: [String: ProjectEditJSON], _ allowed: Set<String>) throws {
        guard Set(value.keys.map { Data($0.utf8) }).isSubset(of: Set(allowed.map { Data($0.utf8) })) else { throw Reason.unsupported }
    }
    private static func token(_ value: ProjectEditJSON?, allowed: [String]) -> String? {
        guard let raw = value?.text else { return nil }; return allowed.first { exact(raw, $0) }
    }
    private static func text(_ raw: ProjectEditJSON?, limit: Int = 64) throws -> String {
        guard let text = raw?.text, !text.isEmpty, text.utf8.elementsEqual(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8), text.utf16.count <= limit else { throw Reason.unsupported }; return text
    }
    private static func list(_ raw: ProjectEditJSON?) throws -> [ProjectEditJSON] {
        guard let raw else { return [] }; guard let rows = raw.array, rows.count <= 512 else { throw Reason.unsupported }; return rows
    }
    private static func number(_ raw: ProjectEditJSON?) -> Bool { if case .number? = raw { return true }; return false }
    private static func optionalInteger(_ raw: ProjectEditJSON?, range: ClosedRange<Int>) throws {
        guard let raw else { return }; guard let n = raw.integer, range.contains(n) else { throw Reason.unsupported }
    }
    private static func optionalBool(_ raw: ProjectEditJSON?) throws {
        guard let raw else { return }; guard raw == .bool(true) || raw == .bool(false) else { throw Reason.unsupported }
    }
    private struct Outcome { let type: String, code: String, label: String }
    /// Mirrors the saved mini node-outcome-contract extractor, but malformed or
    /// incomplete snapshots stay read-only instead of receiving guessed defaults.
    private static func outcomes(_ node: ProjectEditNode) throws -> [Outcome] {
        guard let templateID = node.templateID, templateID > 0,
              let info = node.localMetadata["templateInfo"]?.object, info["id"]?.integer == templateID,
              let method = info["validationMethod"]?.integer, [0, 1, 2, 3, 6, 7].contains(method) else { throw Reason.outcomes }
        func document(_ raw: ProjectEditJSON?) throws -> [String: ProjectEditJSON]? {
            guard let raw, raw != .null, raw != .string("") else { return nil }
            guard let text = raw.text, text.utf8.count <= 262_144 else { throw Reason.outcomes }
            return try graphDocument(text)
        }
        var result: [Outcome] = []
        if method == 6 {
            guard let preference = try document(info["preferenceJson"]), let results = preference["results"]?.object, !results.isEmpty else { throw Reason.outcomes }
            for code in results.keys.sorted() {
                guard let row = results[code]?.object else { throw Reason.outcomes }
                result.append(.init(type: "PREFERENCE_RESULT", code: code, label: row["title"]?.text ?? code))
            }
        }
        if let advanced = try document(info["advancedConfigJson"]) {
            guard advanced["schemaVersion"] == .number(1) else { throw Reason.outcomes }
            if let raw = advanced["branch"] {
                guard let branch = raw.object else { throw Reason.outcomes }; try optionalBool(branch["enabled"])
                if branch["enabled"] == .bool(true) {
                    guard let steps = branch["steps"]?.array, !steps.isEmpty, steps.count <= 128 else { throw Reason.outcomes }
                    for rawStep in steps {
                        guard let step = rawStep.object else { throw Reason.outcomes }; try optionalBool(step["terminal"])
                        if step["terminal"] == .bool(true) {
                            guard let code = step["outcomeCode"]?.text else { throw Reason.outcomes }
                            result.append(.init(type: "ADVANCED_RESULT", code: code, label: step["outcomeLabel"]?.text ?? step["title"]?.text ?? code))
                        }
                    }
                    guard !result.isEmpty else { throw Reason.outcomes }
                }
            }
            if let raw = advanced["diceRoll"] {
                guard let dice = raw.object else { throw Reason.outcomes }; try optionalBool(dice["enabled"])
                if result.isEmpty && dice["enabled"] == .bool(true) {
                    guard dice["mode"] == .string("d20") else { throw Reason.outcomes }
                    result = [.init(type: "ADVANCED_RESULT", code: "D20_SUCCESS", label: "D20_SUCCESS"), .init(type: "ADVANCED_RESULT", code: "D20_FAILURE", label: "D20_FAILURE")]
                }
            }
        }
        if result.isEmpty { result = [.init(type: "CHOICE", code: "COMPLETED", label: "COMPLETED")] }
        guard result.count <= 128, Set(result.map { Data($0.code.utf8) }).count == result.count,
              result.allSatisfy({ item in
                  let bytes = Array(item.code.utf8)
                  return (1...64).contains(bytes.count) && (65...90).contains(bytes[0]) && bytes.allSatisfy { (65...90).contains($0) || (48...57).contains($0) || $0 == 95 }
              }) else { throw Reason.outcomes }
        return result
    }

    private static func validate(_ root: [String: ProjectEditJSON], nodes: [ProjectEditNode]) throws {
        try keys(root, ["schemaVersion", "startNodeId", "terminalNodeIds", "variables", "edges", "fallbacks", "nodeRequirements"])
        guard root["schemaVersion"] == .number(1), let start = nodeID(root["startNodeId"]), let terminalsRaw = root["terminalNodeIds"]?.array,
              !terminalsRaw.isEmpty, let edgesRaw = root["edges"]?.array, edgesRaw.count <= 512 else { throw Reason.unsupported }
        let ids = Set(nodes.compactMap { $0.localMetadata["id"]?.integer })
        func reference(_ raw: ProjectEditJSON?) throws -> Int {
            guard let id = nodeID(raw), ids.contains(id) else { throw Reason.identity }; return id
        }
        guard ids.contains(start) else { throw Reason.identity }
        let terminals = try Set(terminalsRaw.map { try reference($0) })
        guard terminals.count == terminalsRaw.count else { throw Reason.identity }
        let variables: Set<Data>
        if let raw = root["variables"] {
            guard let object = raw.object else { throw Reason.unsupported }
            variables = Set(object.keys.map { Data($0.utf8) })
        } else { variables = [] }
        var gated = Set<Int>()
        for raw in try list(root["nodeRequirements"]) {
            guard let requirement = raw.object else { throw Reason.unsupported }
            try keys(requirement, ["nodeId", "allowedTicketIds", "allowedPurchaseKinds", "requiredRoleCodes", "requireOpen", "requireReachable", "maxDistanceMeters"])
            let id = try reference(requirement["nodeId"]); guard gated.insert(id).inserted else { throw Reason.identity }
            for key in ["allowedTicketIds", "allowedPurchaseKinds"] where requirement[key] != nil {
                let values = try list(requirement[key]), numbers = values.compactMap(\.integer)
                guard !values.isEmpty, values.count == numbers.count, Set(numbers).count == numbers.count,
                      numbers.allSatisfy({ $0 > 0 && (key != "allowedPurchaseKinds" || $0 <= 3) }) else { throw Reason.unsupported }
            }
            if requirement["requiredRoleCodes"] != nil {
                let values = try list(requirement["requiredRoleCodes"]), roles = values.compactMap(\.text)
                guard !values.isEmpty, values.count == roles.count, Set(roles).count == roles.count,
                      Set(roles.map { Data($0.utf8) }).isSubset(of: Set(["NAVIGATOR", "OBSERVER", "RECORDER", "NEGOTIATOR", "DECODER"].map { Data($0.utf8) })) else { throw Reason.unsupported }
            }
            try optionalBool(requirement["requireOpen"]); try optionalBool(requirement["requireReachable"])
            if let distance = requirement["maxDistanceMeters"] {
                guard case .number(let n) = distance, n > 0, n <= 1_000_000 else { throw Reason.unsupported }
            }
        }
        var adjacency: [Int: [Int]] = [:], reverse: [Int: [Int]] = [:], outgoing: [Int: Int] = [:]
        func add(_ from: Int, _ to: Int) { adjacency[from, default: []].append(to); reverse[to, default: []].append(from) }
        var edgeIDs = Set<Data>(), displayedEdgeIDs = Set<String>()
        var parsed: [(from: Int, to: Int, loop: Bool, visits: Int)] = []
        var declared: [Int: [Outcome]] = [:]
        for raw in edgesRaw {
            guard let edge = raw.object else { throw Reason.unsupported }
            try keys(edge, ["id", "fromNodeId", "toNodeId", "trigger", "conditions", "effects", "weight", "priority", "once", "maxVisits", "allowLoop"])
            let id = try text(edge["id"]); guard edgeIDs.insert(Data(id.utf8)).inserted else { throw Reason.ambiguous }
            // SwiftUI's String identity cannot safely distinguish canonical aliases.
            // Distinct exact server IDs that collide there remain unsupported.
            guard displayedEdgeIDs.insert(id).inserted else { throw Reason.unsupported }
            let from = try reference(edge["fromNodeId"]), to = try reference(edge["toNodeId"])
            guard !terminals.contains(from), let trigger = edge["trigger"]?.object else { throw Reason.unsupported }
            try keys(trigger, ["type", "outcomeCode"])
            let type = try text(trigger["type"], limit: 32), code = try text(trigger["outcomeCode"])
            if declared[from] == nil { declared[from] = try outcomes(nodes.first { $0.localMetadata["id"]?.integer == from }!) }
            guard declared[from]!.contains(where: { Self.exact($0.type, type) && Self.exact($0.code, code) }) else { throw Reason.outcomes }
            for rawCondition in try list(edge["conditions"]) {
                guard let condition = rawCondition.object else { throw Reason.unsupported }
                switch token(condition["op"], allowed: ["NODE_COMPLETED", "HAS_TAG", "EQ", "NE", "GT", "GTE", "LT", "LTE"]) {
                case "NODE_COMPLETED": try keys(condition, ["op", "nodeId"]); _ = try reference(condition["nodeId"])
                case "HAS_TAG": try keys(condition, ["op", "value"]); _ = try text(condition["value"])
                case "EQ", "NE", "GT", "GTE", "LT", "LTE":
                    try keys(condition, ["op", "var", "value"])
                    guard variables.contains(Data(try text(condition["var"]).utf8)), number(condition["value"]) else { throw Reason.unsupported }
                default: throw Reason.unsupported
                }
            }
            for rawEffect in try list(edge["effects"]) {
                guard let effect = rawEffect.object else { throw Reason.unsupported }
                switch token(effect["op"], allowed: ["ADD_TAG", "SET", "INC"]) {
                case "ADD_TAG": try keys(effect, ["op", "value"]); _ = try text(effect["value"])
                case "SET", "INC":
                    try keys(effect, ["op", "var", "value"])
                    guard variables.contains(Data(try text(effect["var"]).utf8)), number(effect["value"]) else { throw Reason.unsupported }
                default: throw Reason.unsupported
                }
            }
            try optionalInteger(edge["weight"], range: 1...10000); try optionalInteger(edge["priority"], range: -1000...1000)
            try optionalInteger(edge["maxVisits"], range: 0...10000); try optionalBool(edge["once"]); try optionalBool(edge["allowLoop"])
            parsed.append((from, to, edge["allowLoop"] == .bool(true), edge["maxVisits"]?.integer ?? 0))
            add(from, to); outgoing[from, default: 0] += 1
        }
        var fallbacks: [Int: Int] = [:]
        for raw in try list(root["fallbacks"]) {
            guard let fallback = raw.object else { throw Reason.unsupported }; try keys(fallback, ["fromNodeId", "toNodeId"])
            let from = try reference(fallback["fromNodeId"]), to = try reference(fallback["toNodeId"])
            guard fallbacks[from] == nil, !terminals.contains(from), !gated.contains(to) else { throw Reason.fallback }
            fallbacks[from] = to; add(from, to)
        }
        for (from, count) in outgoing where count > 1 && fallbacks[from] == nil { throw Reason.fallback }
        for edge in parsed where gated.contains(edge.to) && fallbacks[edge.from] == nil { throw Reason.fallback }
        // SCC checks cover every affected edge, including old edges newly placed in
        // a cycle. A fallback can never participate in a cycle, even a bounded one.
        var nextIndex = 0, indices: [Int: Int] = [:], low: [Int: Int] = [:], stack: [Int] = [], onStack = Set<Int>(), component: [Int: Int] = [:]
        func visit(_ node: Int) {
            indices[node] = nextIndex; low[node] = nextIndex; nextIndex += 1; stack.append(node); onStack.insert(node)
            for to in adjacency[node] ?? [] {
                if indices[to] == nil { visit(to); low[node] = min(low[node]!, low[to]!) }
                else if onStack.contains(to) { low[node] = min(low[node]!, indices[to]!) }
            }
            if low[node] == indices[node] {
                while let value = stack.popLast() { onStack.remove(value); component[value] = node; if value == node { break } }
            }
        }
        for id in ids where indices[id] == nil { visit(id) }
        for edge in parsed where component[edge.from] == component[edge.to] {
            guard edge.loop && edge.visits > 0 else { throw Reason.cycle }
        }
        for (from, to) in fallbacks where component[from] == component[to] { throw Reason.cycle }
        func reachable(_ starts: Set<Int>, in graph: [Int: [Int]]) -> Set<Int> {
            var found = starts, queue = Array(starts), cursor = 0
            while cursor < queue.count { let node = queue[cursor]; cursor += 1; for next in graph[node] ?? [] where found.insert(next).inserted { queue.append(next) } }
            return found
        }
        guard reachable([start], in: adjacency) == ids, reachable(terminals, in: reverse) == ids else { throw Reason.reachability }
    }

    /// Locates a token only after the shared strict parser has checked grammar,
    /// duplicate/escaped-alias keys, UTF-8, depth and size. No JSON reserialization.
    private struct TokenScanner {
        let bytes: [UInt8], wanted: [String]
        var cursor = 0
        var found: Range<Int>?
        mutating func spaces() { while cursor < bytes.count && [9, 10, 13, 32].contains(bytes[cursor]) { cursor += 1 } }
        mutating func string() throws -> Range<Int> {
            let start = cursor; guard cursor < bytes.count, bytes[cursor] == 34 else { throw Reason.unsupported }; cursor += 1
            while cursor < bytes.count {
                let byte = bytes[cursor]; cursor += 1
                if byte == 92 { cursor += 1 }
                else if byte == 34 { return start..<cursor }
            }
            throw Reason.unsupported
        }
        mutating func value(path: [String]) throws {
            spaces(); let start = cursor; guard cursor < bytes.count else { throw Reason.unsupported }
            switch bytes[cursor] {
            case 123:
                cursor += 1; spaces()
                if bytes[cursor] != 125 {
                    while true {
                        spaces(); let keyRange = try string(), key = try JSONDecoder().decode(String.self, from: Data(bytes[keyRange]))
                        spaces(); cursor += 1; try value(path: path + [key]); spaces()
                        if bytes[cursor] == 125 { break }; cursor += 1
                    }
                }
                cursor += 1
            case 91:
                cursor += 1; spaces(); var index = 0
                if bytes[cursor] != 93 {
                    while true { try value(path: path + [String(index)]); index += 1; spaces(); if bytes[cursor] == 93 { break }; cursor += 1 }
                }
                cursor += 1
            case 34: _ = try string()
            default: while cursor < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[cursor]) { cursor += 1 }
            }
            if path == wanted { guard found == nil else { throw Reason.ambiguous }; found = start..<cursor }
        }
    }
}
