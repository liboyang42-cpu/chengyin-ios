import Foundation

/// P034: staged edits of the original themeRuntimeConfig; never a second topic writer.
public struct NativeRuntimeStructureAuthorDraft: Equatable {
    public enum Mode: String, CaseIterable, Identifiable {
        case player = "PLAYER", team = "TEAM_INDEPENDENT", sharedWorld = "WORLD_SHARED"
        public var id: String { rawValue }
        public var shared: Bool { self == .sharedWorld }
        public var scope: String { self == .player ? "PLAYER" : "TEAM" }
        public var title: String { switch self { case .player: return "个人独立进行"; case .team: return "队伍独立进行"; case .sharedWorld: return "队伍共用现场" } }
        public var summary: String { switch self { case .player: return "每人独立完成任务、支付资源；不使用工作人员开幕或跨队交易、表决。"; case .team: return "同队共用任务进度和资源，各队分别完成；工作人员可开幕、核验到达和引导答题。"; case .sharedWorld: return "各队保留自己的资源，在同一现场交易、投入和表决；工作人员可开幕和引导。" } }
    }
    public struct Choice: Identifiable, Equatable { public let id: String; public let label: String }
    public struct ActReference: Identifiable, Equatable {
        public let kind: String, index: Int, title: String, selected: [String]
        public var id: String { kind + ":" + String(index) }
        public var multiple: Bool { kind == "recoveries" }
    }
    public let original: ProjectEditDraft
    private let originalBytes: Data
    public private(set) var theme: [String: ProjectEditJSON]
    public private(set) var notices: [String] = []
    public init(draft: ProjectEditDraft) throws {
        original = draft
        guard let exact = ProjectEditPendingMaterials.exactData(draft) else { throw ProjectEditError.invalidDraft }; originalBytes = exact
        theme = try Self.readTheme(draft)
        guard theme.isEmpty || theme["schemaVersion"] == .number(1),
              theme["gameplayRuntime"] == nil || theme["gameplayRuntime"]?.object != nil else { throw ProjectEditError.invalidDraft }
        for field in ["acts", "quests", "facilities"] {
            if let value = game[field] {
                guard let rows = value.array, rows.allSatisfy({ $0.object != nil }) else { throw ProjectEditError.invalidDraft }
            }
        }
    }
    static func readTheme(_ draft: ProjectEditDraft) throws -> [String: ProjectEditJSON] {
        guard let raw = draft.preserved["themeRuntimeConfig"], raw != .null, raw != .string("") else { return [:] }
        guard let text = raw.text, text.utf16.count <= 200_000 else { throw ProjectEditError.invalidDraft }
        return try ApprovedTopicReleaseWire.envelope(Data(text.utf8))
    }
    public var game: [String: ProjectEditJSON] { theme["gameplayRuntime"]?.object ?? [:] }
    public var mode: Mode? {
        if game["runtimeScope"] == .string("PLAYER") { return .player }
        guard game["runtimeScope"] == .string("TEAM"), let value = game["worldMode"]?.text.flatMap(Mode.init(rawValue:)), value != .player else { return nil }; return value
    }
    public var acts: [[String: ProjectEditJSON]] { (game["acts"]?.array ?? []).compactMap(\.object) }
    public var quests: [[String: ProjectEditJSON]] { (game["quests"]?.array ?? []).compactMap(\.object) }
    public var nodes: [ProjectEditNode] { original.chapters.flatMap(\.nodes) }
    public var savedNodes: [ProjectEditNode] { nodes.filter { ($0.localMetadata["id"]?.integer ?? 0) > 0 } }
    public var challengeIDs: Set<Int> {
        let zero = game["survival"]?.object?["zeroChallenge"]?.object ?? [:]
        return Set([zero["challengeNodeId"]].compactMap { $0?.integer } + (zero["alternativeNodeIds"]?.array ?? []).compactMap(\.integer))
    }
    private mutating func updateGame(_ value: [String: ProjectEditJSON]) { theme["gameplayRuntime"] = .object(value) }
    public func modeReason(_ mode: Mode, inputs: NativeRuntimeStructureAuthorInputs) -> String? {
        if mode == .player && acts.contains(where: { $0["hostUnlock"] == .bool(true) }) { return "请先关闭章节的工作人员开幕" }
        if !mode.shared && (game["allowTrade"] == .bool(true) || game["votePolicy"] != nil || !(game["plans"]?.array ?? []).isEmpty || (game["facilities"]?.array ?? []).contains(where: { ($0.object?["scope"]?.text ?? "OWNER") != "OWNER" || ($0.object?["targetScope"]?.text ?? "OWNER") != "OWNER" })) { return "跨队交易、表决和共享设施需要队伍共用现场" }
        for node in nodes { if let reason = inputs.reason(node: node, theme: theme, mode: mode) { return (node.name.isEmpty ? "节点" : node.name) + "：" + reason } }
        return nil
    }
    public mutating func select(_ mode: Mode, inputs: NativeRuntimeStructureAuthorInputs) throws {
        guard modeReason(mode, inputs: inputs) == nil else { throw ProjectEditError.invalidDraft }
        if theme.isEmpty { theme = ["schemaVersion": .number(1), "capacity": .number(0)] }
        var next = game; next["runtimeScope"] = .string(mode.scope)
        next["worldMode"] = mode == .player ? nil : .string(mode.rawValue)
        // Original explicit compiler defaults; never replace an existing survival extension.
        if next["survival"] == nil { next["survival"] = .object(["zeroHpPolicy": .string("BLOCK_HP_COST"), "actionLimitPolicy": .string("BLOCK_OVERFLOW")]) }
        updateGame(next)
    }
    public var synchronizationReason: String? {
        if mode == nil { return "请先选择进行方式" }
        let ids = nodes.compactMap { $0.localMetadata["id"]?.integer }
        if ids.count != nodes.count || ids.contains(where: { $0 < 1 }) || Set(ids).count != ids.count { return "请先保存主题和节点草稿，再设置章节及到达关系" }
        for chapter in original.chapters {
            let members = Set(chapter.nodes.compactMap { $0.localMetadata["id"]?.integer })
            if Set(quests.filter { members.contains($0["nodeId"]?.integer ?? 0) }.compactMap { $0["actKey"]?.text }).count > 1 { return "本章已有多幕配置，请先将幕内任务分别放入对应章节" }
        }
        return nil
    }
    public mutating func synchronizeChapters() throws {
        guard synchronizationReason == nil else { throw ProjectEditError.invalidDraft }
        let previous = quests, oldActs = acts
        var nextActs: [[String: ProjectEditJSON]] = [], nextQuests: [[String: ProjectEditJSON]] = [], copied = 0
        for (index, chapter) in original.chapters.enumerated() {
            let members = chapter.nodes.filter { !challengeIDs.contains($0.localMetadata["id"]?.integer ?? 0) }
            guard !members.isEmpty else { continue }
            let ids = Set(members.compactMap { $0.localMetadata["id"]?.integer })
            let existing = previous.filter { ids.contains($0["nodeId"]?.integer ?? 0) }
            let key: String
            if let old = existing.first?["actKey"]?.text { key = old }
            else if previous.isEmpty && oldActs.indices.contains(copied), let old = oldActs[copied]["actKey"]?.text { key = old; copied += 1 }
            else { key = chapter.preserved["id"]?.integer.map { "chapter_\($0)" } ?? "chapter_index_\(index)" }
            guard !nextActs.contains(where: { $0["actKey"] == .string(key) }) else { throw ProjectEditError.invalidDraft }
            var act = oldActs.first { $0["actKey"] == .string(key) } ?? ["actKey": .string(key), "completionRule": .object(["type": .string("ALL")])]
            if let completion = theme["chapters"]?.array?.first(where: { $0.object?["index"] == .number(Decimal(index)) })?.object?["completion"]?.object {
                var rule: [String: ProjectEditJSON] = ["type": completion["type"] ?? .string("ALL")]
                if completion["type"] == .string("ANY_N") { rule["quantity"] = completion["quantity"] }; act["completionRule"] = .object(rule)
            }
            var keys: [ProjectEditJSON] = []
            for node in members {
                guard let id = node.localMetadata["id"]?.integer else { throw ProjectEditError.invalidDraft }
                let nodeKey = "node_\(id)"
                var quest = previous.first { $0["nodeId"] == .number(Decimal(id)) } ?? ["questKey": .string(nodeKey), "nodeId": .number(Decimal(id)), "locationKey": .string(nodeKey), "settlementSlot": .string(nodeKey)]
                quest["actKey"] = .string(key); nextQuests.append(quest)
                guard let questKey = quest["questKey"] else { throw ProjectEditError.invalidDraft }; keys.append(questKey)
            }
            act["questKeys"] = .array(keys); nextActs.append(act)
        }
        if previous.isEmpty { for old in oldActs.dropFirst(copied) { var act = old; act["questKeys"] = .array([]); nextActs.append(act) } }
        let keys = Set(nextQuests.compactMap { $0["questKey"]?.text })
        for index in nextQuests.indices { if let prerequisites = nextQuests[index]["prerequisites"]?.array { nextQuests[index]["prerequisites"] = .array(prerequisites.filter { $0.text.map(keys.contains) == true }) } }
        var next = game; next["acts"] = .array(nextActs.map(ProjectEditJSON.object)); next["quests"] = .array(nextQuests.map(ProjectEditJSON.object))
        updateGame(next)
        // Keep dangling recovery sets: empty means all acts and must never widen authority.
        notices = danglingActReferences.map { $0.title + "：引用的幕已删除，请重新选择；原规则内容未删除" }
    }
    public var locations: [Choice] {
        var result = savedNodes.compactMap { node -> Choice? in guard let id = node.localMetadata["id"]?.integer else { return nil }; return .init(id: "node_\(id)", label: node.name.isEmpty ? "节点 \(id)" : node.name) }
        for quest in quests { if let key = quest["locationKey"]?.text, !result.contains(where: { $0.id == key }) { result.append(.init(id: key, label: "已有共用地点（\(key)）")) } }
        return result
    }
    public func quest(nodeID: Int) -> [String: ProjectEditJSON]? { quests.first { $0["nodeId"] == .number(Decimal(nodeID)) } }
    private mutating func updateQuest(_ nodeID: Int, change: (inout [String: ProjectEditJSON]) -> Void) throws {
        var rows = quests; guard rows.filter({ $0["nodeId"] == .number(Decimal(nodeID)) }).count == 1, let index = rows.firstIndex(where: { $0["nodeId"] == .number(Decimal(nodeID)) }) else { throw ProjectEditError.invalidDraft }
        change(&rows[index]); var next = game; next["quests"] = .array(rows.map(ProjectEditJSON.object)); updateGame(next)
    }
    public mutating func location(nodeID: Int, key: String) throws {
        guard locations.contains(where: { $0.id == key }) else { throw ProjectEditError.invalidDraft }; try updateQuest(nodeID) { $0["locationKey"] = .string(key) }
    }
    public mutating func guide(nodeID: Int, enabled: Bool, inputs: NativeRuntimeStructureAuthorInputs) throws {
        guard let node = savedNodes.first(where: { $0.localMetadata["id"]?.integer == nodeID }), !enabled || inputs.guideAllowed(node, theme: theme) else { throw ProjectEditError.invalidDraft }
        try updateQuest(nodeID) { row in row["guideKey"] = enabled ? (row["guideKey"] ?? .string("guide_\(nodeID)")) : nil }
    }
    public mutating func fallback(nodeID: Int, other: Int, selected: Bool) throws {
        guard other != nodeID, savedNodes.contains(where: { $0.localMetadata["id"]?.integer == other }) else { throw ProjectEditError.invalidDraft }
        var ids = (quest(nodeID: nodeID)?["approvedFallbackNodeIds"]?.array ?? []).compactMap(\.integer)
        ids.removeAll { $0 == other }; if selected { ids.append(other) }
        guard ids.count <= 20 else { throw ProjectEditError.invalidDraft }
        try updateQuest(nodeID) { $0["approvedFallbackNodeIds"] = .array(ids.map { .number(Decimal($0)) }) }
    }
    /// Explicitly remove a deleted fallback; no silent pruning of the author's choices.
    public mutating func removeStaleFallback(nodeID: Int, other: Int) throws {
        try updateQuest(nodeID) { $0["approvedFallbackNodeIds"] = .array(($0["approvedFallbackNodeIds"]?.array ?? []).filter { $0.integer != other }) }
    }
    public mutating func host(actKey: String, enabled: Bool) throws {
        guard !enabled || mode != .player, mode != nil else { throw ProjectEditError.invalidDraft }
        var rows = acts; guard let index = rows.firstIndex(where: { $0["actKey"]?.text == actKey }) else { throw ProjectEditError.invalidDraft }
        rows[index]["hostUnlock"] = .bool(enabled); var next = game; next["acts"] = .array(rows.map(ProjectEditJSON.object)); updateGame(next)
    }
    public var actReferences: [ActReference] {
        var result: [ActReference] = []
        for kind in ["facilities", "rations", "recoveries"] {
            let rows = kind == "facilities" ? game[kind]?.array ?? [] : game["survival"]?.object?[kind]?.array ?? []
            for (index, value) in rows.enumerated() { let row = value.object ?? [:]
                let selected = kind == "recoveries" ? (row["actKeys"]?.array ?? []).compactMap(\.text) : [row["actKey"]?.text].compactMap { $0 }
                result.append(.init(kind: kind, index: index, title: (kind == "facilities" ? "已有设施" : kind == "rations" ? "已有配给" : "已有恢复") + " \(index + 1)", selected: selected))
            }
        }; return result
    }
    public var danglingActReferences: [ActReference] {
        let keys = Set(acts.compactMap { $0["actKey"]?.text })
        return actReferences.filter { (!$0.multiple && $0.selected.count != 1) || !$0.selected.allSatisfy(keys.contains) }
    }
    /// Repair only an existing legacy reference. This does not restore retired creation forms.
    public mutating func repair(_ reference: ActReference, selected: [String]) throws {
        guard actReferences.contains(reference), !selected.isEmpty, (!reference.multiple ? selected.count == 1 : true), Set(selected).count == selected.count,
              selected.allSatisfy({ key in acts.contains { $0["actKey"]?.text == key } }) else { throw ProjectEditError.invalidDraft }
        var next = game, survival = next["survival"]?.object ?? [:]
        var rows = reference.kind == "facilities" ? next[reference.kind]?.array ?? [] : survival[reference.kind]?.array ?? []
        guard rows.indices.contains(reference.index), var row = rows[reference.index].object else { throw ProjectEditError.invalidDraft }
        row[reference.multiple ? "actKeys" : "actKey"] = reference.multiple ? .array(selected.map(ProjectEditJSON.string)) : .string(selected[0]); rows[reference.index] = .object(row)
        if reference.kind == "facilities" { next[reference.kind] = .array(rows) } else { survival[reference.kind] = .array(rows); next["survival"] = .object(survival) }; updateGame(next)
    }
    public var issues: [String] {
        var result: [String] = []
        if mode == nil { result.append("请选择个人或队伍的进行方式") }
        if mode == .player && acts.contains(where: { $0["hostUnlock"] == .bool(true) }) { result.append("个人独立进行不能设置工作人员开幕") }
        let ids = Set(savedNodes.compactMap { $0.localMetadata["id"]?.integer }), actKeys = acts.compactMap { $0["actKey"]?.text }, questKeys = quests.compactMap { $0["questKey"]?.text }
        if actKeys.count != acts.count || Set(actKeys).count != acts.count || questKeys.count != quests.count || Set(questKeys).count != quests.count { result.append("幕或任务身份重复，请按真实章节重新同步") }
        for act in acts {
            let key = act["actKey"]?.text ?? "", members = act["questKeys"]?.array ?? []
            let memberKeys = members.compactMap(\.text)
            if members.count != memberKeys.count || Set(memberKeys).count != members.count || Set(memberKeys) != Set(quests.filter { $0["actKey"]?.text == key }.compactMap { $0["questKey"]?.text }) { result.append("幕内任务清单已变化，请重新同步章节") }
        }
        for row in quests {
            guard let id = row["nodeId"]?.integer, ids.contains(id), !challengeIDs.contains(id) else { result.append("任务节点已改变或是归零挑战，请重新同步章节"); continue }
            if !actKeys.contains(row["actKey"]?.text ?? "") { result.append("任务对应幕已删除，请重新同步章节") }
            let fallback = row["approvedFallbackNodeIds"]?.array ?? [], values = fallback.compactMap(\.integer)
            if values.count != fallback.count || values.count > 20 || Set(values).count != values.count || values.contains(where: { !ids.contains($0) || $0 == id }) { result.append("节点 \(id)：备用节点须从本主题其他节点选择，最多 20 个且不能重复") }
            if row["locationKey"]?.text?.range(of: "^[a-z][a-z0-9_]{0,31}$", options: .regularExpression) == nil { result.append("节点 \(id)：请选择到达地点") }
            if (row["prerequisites"]?.array ?? []).contains(where: { !questKeys.contains($0.text ?? "") }) { result.append("任务前置已删除，请重新同步章节") }
        }
        result += danglingActReferences.map { $0.title + "：引用的幕已删除，请重新选择" }
        return Array(Set(result)).sorted()
    }
    public func applying(to draft: ProjectEditDraft, inputs: NativeRuntimeStructureAuthorInputs) throws -> ProjectEditDraft {
        guard ProjectEditPendingMaterials.exactData(draft) == originalBytes else { throw ProjectEditError.changedSession }
        guard issues.isEmpty, let mode, modeReason(mode, inputs: inputs) == nil else { throw ProjectEditError.invalidDraft }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ProjectEditJSON.object(theme)); guard let text = String(data: data, encoding: .utf8), text.utf16.count <= 200_000 else { throw ProjectEditError.invalidDraft }
        var next = draft; next.preserved["themeRuntimeConfig"] = .string(text); return next
    }
    /// Only current structure dependencies; do not infer gameplay rules from unrelated fields.
    public static func validateOriginalSubmission(_ draft: ProjectEditDraft) throws {
        let theme = try readTheme(draft)
        guard let game = theme["gameplayRuntime"]?.object, game["runtimeScope"] != nil,
              theme["schemaVersion"] == .number(1) else { return }
        let staged = try Self(draft: draft)
        guard staged.issues.isEmpty else { throw ProjectEditError.invalidDraft }
    }
}
