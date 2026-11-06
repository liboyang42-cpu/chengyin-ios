import Foundation

/// P034's staged zero-HP panel. Only the original themeRuntimeConfig is edited.
/// Defaults and bounds follow the c6 theme-runtime-zero-hp.js read/validate contract.
public struct NativeZeroHPAuthorDraft: Equatable {
    public enum Policy: String, CaseIterable, Identifiable {
        case block = "BLOCK_HP_COST", fail = "THEME_FAIL", challenge = "CHALLENGE", steps = "STEPS", wait = "WAIT"
        public var id: String { rawValue }
        public var title: String {
            switch self { case .block: return "仅禁止扣该值的任务"; case .fail: return "主题失败"; case .challenge: return "完成恢复挑战"; case .steps: return "走够步数"; case .wait: return "等待一段时间" }
        }
        public var blockKey: String? { switch self { case .challenge: return "zeroChallenge"; case .steps: return "zeroSteps"; case .wait: return "zeroWait"; default: return nil } }
    }
    public let original: ProjectEditDraft
    public let theme: [String: ProjectEditJSON]
    private let originalBytes: Data
    public private(set) var policy: String
    public private(set) var zeroMessage: String
    public private(set) var blocks: [String: [String: ProjectEditJSON]]
    private let initialPolicy: String, initialMessage: String
    private let initialBlocks: [String: [String: ProjectEditJSON]]
    public let readOnly: Bool
    public init(draft: ProjectEditDraft) throws {
        original = draft
        guard let bytes = ProjectEditPendingMaterials.exactData(draft) else { throw ProjectEditError.invalidDraft }; originalBytes = bytes
        theme = try NativeRuntimeStructureAuthorDraft.readTheme(draft)
        guard theme["gameplayRuntime"] == nil || theme["gameplayRuntime"]?.object != nil,
              theme["gameplayRuntime"]?.object?["survival"] == nil || theme["gameplayRuntime"]?.object?["survival"]?.object != nil else { throw ProjectEditError.invalidDraft }
        let survival = theme["gameplayRuntime"]?.object?["survival"]?.object ?? [:]
        guard survival["zeroHpPolicy"] == nil || survival["zeroHpPolicy"]?.text != nil,
              survival["zeroMessage"] == nil || survival["zeroMessage"]?.text != nil else { throw ProjectEditError.invalidDraft }
        policy = survival["zeroHpPolicy"]?.text ?? Policy.block.rawValue
        zeroMessage = survival["zeroMessage"]?.text ?? ""
        var values: [String: [String: ProjectEditJSON]] = [:]
        for kind in [Policy.challenge, .steps, .wait] {
            let key = kind.blockKey!
            if let value = survival[key] { guard let object = value.object else { throw ProjectEditError.invalidDraft }; values[key] = object }
            else {
                var row: [String: ProjectEditJSON] = ["version": .number(kind == .challenge ? 2 : 1), "restoreTo": .number(1), "limit": .number(1), "thenPolicy": .string("THEME_FAIL")]
                switch kind {
                case .challenge: row.merge(["gameplayKey": .string(""), "challengeNodeId": .null, "alternativeNodeIds": .array([]), "requiredCompletions": .number(1), "withinSeconds": .number(60)]) { _, new in new }
                case .steps: row["steps"] = .number(2000)
                case .wait: row["minutes"] = .number(30)
                default: break
                }; values[key] = row
            }
        }
        blocks = values; initialPolicy = policy; initialMessage = zeroMessage; initialBlocks = values
        let selected = Policy(rawValue: policy)
        readOnly = selected == nil || selected == .steps || (!theme.isEmpty && theme["schemaVersion"] != .number(1))
            || (selected == .challenge && survival["zeroChallenge"]?.object?["version"] != .number(2))
            || (selected == .wait && survival["zeroWait"] != nil && survival["zeroWait"]?.object?["version"] != .number(1))
    }
    public var selected: Policy? { Policy(rawValue: policy) }
    public var rpgResources: NativeRpgResourceAuthorDraft? { try? .init(draft: original) }
    public var hp: ProjectInitialState.Resource {
        if let resources = rpgResources {
            // Installed schema2 declarations are read through their existing author
            // contract, never downgraded to schema1 or filled with new defaults.
            return .init(enabled: resources.rules["hp"]?.object?["enabled"] == .bool(true),
                         initial: resources.text("hp", "init"), maximum: resources.text("hp", "max"))
        }
        return ProjectInitialState(raw: original.preserved["journeyRules"]).hp
    }
    public var hpEditorName: String { rpgResources == nil ? "第一章初始状态" : "原 RPG 数值资源" }
    public var hpName: String { theme["hpName"]?.text ?? "生命值" }
    public var savedNodes: [ProjectEditNode] { original.chapters.flatMap(\.nodes).filter { ($0.localMetadata["id"]?.integer ?? 0) > 0 } }
    public var challenge: [String: ProjectEditJSON] { blocks["zeroChallenge"] ?? [:] }
    public var alternatives: [Int] { (challenge["alternativeNodeIds"]?.array ?? []).compactMap(\.integer) }
    public var isUnchanged: Bool {
        // JavaScript compares the author's original spelling. Swift String equality
        // normalizes NFC/NFD; a changed reply must still reach the original writer.
        guard let current = ProjectEditPendingMaterials.exactData(blocks),
              let initial = ProjectEditPendingMaterials.exactData(initialBlocks) else { return false }
        return policy.utf8.elementsEqual(initialPolicy.utf8)
            && zeroMessage.utf8.elementsEqual(initialMessage.utf8)
            && current == initial
    }
    public var compatibilitySummary: String {
        let name = selected?.title ?? (["BLOCK_PAID": "禁止所有收费动作", "LEGACY_END": "旧版结束"][policy] ?? policy)
        let row = blocks[selected?.blockKey ?? ""] ?? [:]
        let quantity: String?
        switch selected {
        case .some(.challenge): quantity = row["challengeNodeId"]?.integer.map { "节点 \($0)" }
        case .some(.wait): quantity = row["minutes"]?.integer.map { "\($0) 分钟" }
        case .some(.steps): quantity = row["steps"]?.integer.map { "\($0) 步" }
        default: quantity = nil
        }
        return [name, quantity, zeroMessage.isEmpty ? nil : zeroMessage].compactMap { $0 }.joined(separator: " · ")
    }
    public mutating func select(_ next: Policy, inputs: NativeRuntimeStructureAuthorInputs) throws {
        guard !readOnly, NativeZeroHPAuthorPolicy.reason(next, draft: self, inputs: inputs) == nil else { throw ProjectEditError.invalidDraft }; policy = next.rawValue
    }
    public mutating func message(_ value: String) { guard !readOnly else { return }; zeroMessage = value }
    public func text(_ field: String) -> String {
        guard let key = selected?.blockKey, let value = blocks[key]?[field] else { return "" }
        return value.text ?? value.integer.map(String.init) ?? ""
    }
    public mutating func number(_ field: String, text: String) {
        guard !readOnly, let kind = selected, let key = kind.blockKey else { return }
        var fields: Set<String> = ["restoreTo", "limit"]
        if kind == .challenge { fields.formUnion(["requiredCompletions", "withinSeconds"]) }
        if kind == .steps { fields.insert("steps") }; if kind == .wait { fields.insert("minutes") }
        guard fields.contains(field) else { return }
        blocks[key]?[field] = Int(text).map { .number(Decimal($0)) } ?? .string(text)
    }
    public mutating func then(_ value: Policy) throws {
        guard !readOnly, let key = selected?.blockKey, [Policy.fail, .block].contains(value) else { throw ProjectEditError.invalidDraft }; blocks[key]?["thenPolicy"] = .string(value.rawValue)
    }
    public mutating func main(nodeID: Int, inputs: NativeRuntimeStructureAuthorInputs) throws {
        guard !readOnly, let node = savedNodes.first(where: { $0.localMetadata["id"]?.integer == nodeID }),
              NativeZeroHPAuthorPolicy.nodeReason(node, draft: self, inputs: inputs) == nil else { throw ProjectEditError.invalidDraft }
        let advanced = try inputs.advanced(node, theme: theme)
        guard let section = inputs.mainRows(advanced, recoveryV2: true).first?["section"]?.text else { throw ProjectEditError.invalidDraft }
        blocks["zeroChallenge"]?["challengeNodeId"] = .number(Decimal(nodeID)); blocks["zeroChallenge"]?["gameplayKey"] = .string(section)
        let remainingAlternatives = alternatives.filter { $0 != nodeID }
        blocks["zeroChallenge"]?["alternativeNodeIds"] = .array(remainingAlternatives.map { .number(Decimal($0)) })
    }
    public mutating func alternative(nodeID: Int, selected: Bool, inputs: NativeRuntimeStructureAuthorInputs) throws {
        guard !readOnly else { throw ProjectEditError.invalidDraft }
        var ids = alternatives.filter { $0 != nodeID }
        if selected {
            guard nodeID != challenge["challengeNodeId"]?.integer, ids.count < 3,
                  let node = savedNodes.first(where: { $0.localMetadata["id"]?.integer == nodeID }),
                  NativeZeroHPAuthorPolicy.nodeReason(node, draft: self, inputs: inputs) == nil else { throw ProjectEditError.invalidDraft }; ids.append(nodeID)
        }
        blocks["zeroChallenge"]?["alternativeNodeIds"] = .array(ids.map { .number(Decimal($0)) })
    }
    /// Only the selected policy owns its payload. All unrelated survival/scene/RPG fields survive.
    public var proposedTheme: [String: ProjectEditJSON] {
        guard !readOnly, !isUnchanged else { return theme }
        var next = theme, game = next["gameplayRuntime"]?.object ?? [:], survival = game["survival"]?.object ?? [:]
        if next.isEmpty { next = ["schemaVersion": .number(1), "capacity": .number(0)] }
        survival["zeroHpPolicy"] = .string(policy); survival["zeroMessage"] = zeroMessage.isEmpty ? nil : .string(zeroMessage)
        for kind in [Policy.challenge, .steps, .wait] { let key = kind.blockKey!; survival[key] = selected == kind ? blocks[key].map(ProjectEditJSON.object) : nil }
        if policy == Policy.block.rawValue && survival.count == 1 { survival = [:] }
        game["survival"] = survival.isEmpty ? nil : .object(survival); next["gameplayRuntime"] = game.isEmpty ? nil : .object(game)
        return next
    }
    static func replacingTheme(_ theme: [String: ProjectEditJSON], in draft: ProjectEditDraft) throws -> ProjectEditDraft {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(ProjectEditJSON.object(theme)), text = String(decoding: bytes, as: UTF8.self)
        guard text.utf16.count <= 200_000 else { throw ProjectEditError.invalidDraft }
        var next = draft; next.preserved["themeRuntimeConfig"] = .string(text); return next
    }
    /// Reuse the installed original structure reconciliation, not a parallel quest compiler.
    public func synchronizedTheme() throws -> [String: ProjectEditJSON] {
        let next = proposedTheme
        guard !isUnchanged, (next["gameplayRuntime"]?.object?["acts"]?.array?.isEmpty == false) else { return next }
        var structure = try NativeRuntimeStructureAuthorDraft(draft: Self.replacingTheme(next, in: original))
        try structure.synchronizeChapters()
        return structure.theme
    }
    public func issues(inputs: NativeRuntimeStructureAuthorInputs) -> [String] {
        guard !readOnly else { return [] }
        var result = valueIssues
        if let selected, let reason = NativeZeroHPAuthorPolicy.reason(selected, draft: self, inputs: inputs) { result.append(reason) }
        if selected == .challenge { result += NativeZeroHPAuthorPolicy.challengeIssues(draft: self, inputs: inputs) }
        if (try? synchronizedTheme()) == nil { result.append("请先保存全部节点，并在进行方式与节点引导中修正章节关系后再完成") }
        return Array(Set(result)).sorted()
    }
    public var valueIssues: [String] {
        guard !readOnly else { return [] }
        var result: [String] = []
        let proposedSurvival = proposedTheme["gameplayRuntime"]?.object?["survival"]?.object ?? [:]
        for kind in [Policy.challenge, .steps, .wait] {
            let key = kind.blockKey!
            if selected == kind && proposedSurvival[key]?.object == nil { result.append("请配置所选恢复条件") }
            if selected != kind && proposedSurvival[key] != nil { result.append("只能设置所选的恢复项；请重新选择归零策略后完成") }
        }
        if zeroMessage.utf16.count > 2000 { result.append("归零时回复不能超过 2000 字") }
        guard let selected else { return result + ["请选择有效的 HP 归零策略"] }
        let initial = ProjectInitialState(raw: original.preserved["journeyRules"])
        if let resources = rpgResources {
            if selected != .block && (resources.rules["hp"]?.object?["enabled"] == nil || resources.rules["hp"]?.object?["max"]?.integer == nil) { result.append("原 schema2 HP 声明未明确，请先在原 RPG 数值资源编辑器确认；不代填默认值") }
            result += resources.issues.filter { $0.hasPrefix("hp") }
        } else if initial.readOnly { result.append("生命值域无法读取，请在原值域编辑器检查") }
        if !hp.enabled && selected != .block { result.append("请先在" + hpEditorName + "开启" + hpName) }
        guard let key = selected.blockKey, let row = blocks[key] else { return result }
        func check(_ field: String, _ range: ClosedRange<Int>, _ label: String) {
            if row[field]?.integer.map(range.contains) != true { result.append(label + "须为 \(range.lowerBound) 至 \(range.upperBound) 的整数") }
        }
        if row["version"] != .number(selected == .challenge ? 2 : 1) { result.append("恢复配置版本不受支持") }
        if let maximum = Int(hp.maximum), maximum >= 1 { check("restoreTo", 1...maximum, "恢复值") } else { result.append("请先修正生命值上限") }
        check("limit", 1...99, "最多恢复次数")
        if ![Policy.fail.rawValue, Policy.block.rawValue].contains(row["thenPolicy"]?.text ?? "") { result.append("请选择次数用完后的策略") }
        if selected == .wait { check("minutes", 1...10080, "等待分钟") }
        if selected == .steps { check("steps", 1...100000, "恢复步数") }
        if selected == .challenge {
            check("requiredCompletions", 1...99, "需完成次数"); check("withinSeconds", 1...86400, "恢复挑战限时（秒）")
            let ids = savedNodes.compactMap { $0.localMetadata["id"]?.integer }
            if Set(ids).count != ids.count { result.append("已保存节点身份重复，请重新读取原草稿") }
            if row["challengeNodeId"]?.integer.map({ $0 > 0 && ids.contains($0) }) != true { result.append("请先保存主题和挑战节点，再选择主挑战") }
            let alternatives = row["alternativeNodeIds"]?.array
            if alternatives == nil || alternatives!.count != self.alternatives.count || self.alternatives.count > 3 || Set(self.alternatives).count != self.alternatives.count || self.alternatives.contains(where: { $0 < 1 || $0 == row["challengeNodeId"]?.integer || !ids.contains($0) }) { result.append("备选挑战最多 3 个，不能重复，须为本主题其他真实节点") }
        }
        return result
    }
    public func applying(to draft: ProjectEditDraft, inputs: NativeRuntimeStructureAuthorInputs) throws -> ProjectEditDraft {
        guard ProjectEditPendingMaterials.exactData(draft) == originalBytes else { throw ProjectEditError.changedSession }
        guard !readOnly else { return draft }
        guard issues(inputs: inputs).isEmpty else { throw ProjectEditError.invalidDraft }
        if isUnchanged { return draft }
        return try Self.replacingTheme(synchronizedTheme(), in: draft)
    }
    /// Re-check original numeric/reference constraints after node or initial-state edits.
    /// No new network, review gate or policy grant; server remains the final validator.
    public static func validateOriginalSubmission(_ draft: ProjectEditDraft) throws {
        let theme = try NativeRuntimeStructureAuthorDraft.readTheme(draft)
        guard theme["schemaVersion"] == .number(1), let survival = theme["gameplayRuntime"]?.object?["survival"]?.object,
              survival["zeroHpPolicy"] != nil else { return }
        let buffer = try Self(draft: draft)
        guard buffer.readOnly || buffer.valueIssues.isEmpty else { throw ProjectEditError.invalidDraft }
    }
}
