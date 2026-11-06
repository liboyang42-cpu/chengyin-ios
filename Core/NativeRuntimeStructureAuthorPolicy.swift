import Foundation

/// Read-only projections of the original support-matrix and exact bound member templates.
/// No bundled policy, template adoption, gameplay writer, or publication grant.
public struct NativeRuntimeStructureAuthorInputs: Equatable {
    public static let supportPath = "api/play/theme/support-matrix"
    public static let templatePath = "api/template/myinfo"
    public let matrix: [String: ProjectEditJSON]
    public let templates: [Int: [String: ProjectEditJSON]]
    public init(matrix: [String: ProjectEditJSON], templates: [Int: [String: ProjectEditJSON]]) throws {
        guard matrix["schemaVersion"] == .number(1), let types = matrix["types"]?.array,
              let addons = matrix["addons"]?.array, matrix["constraints"]?.object != nil,
              matrix["legacyProofs"]?.object != nil,
              (types + addons).allSatisfy({ $0.object?["key"]?.text != nil && $0.object?["tools"]?.object != nil }) else { throw ProjectEditError.invalidContract }
        self.matrix = matrix; self.templates = templates
    }
    public func advanced(_ node: ProjectEditNode, theme: [String: ProjectEditJSON]) throws -> [String: ProjectEditJSON] {
        guard let id = node.templateID, id > 0 else { return [:] }
        guard let source = templates[id], source["id"]?.integer == id else { throw ProjectEditError.invalidContract }
        var raw = source["advancedConfigJson"]
        let key = node.localMetadata["id"]?.integer.flatMap { $0 > 0 ? String($0) : nil }
            ?? "client:" + (node.localMetadata["clientNodeKey"]?.text ?? node.id)
        if let scene = theme["scenes"]?.array?.first(where: { $0.object?["id"] == theme["currentScene"] })?.object,
           let override = scene["nodeConfigs"]?.object?[key] { raw = override }
        if raw == nil || raw == .null || raw == .string("") { return [:] }
        if let object = raw?.object { return object } // Existing scene override; never rewrite its representation.
        guard let text = raw?.text, text.utf8.count <= 1_048_576 else { throw ProjectEditError.invalidContract }
        return try ApprovedTopicReleaseWire.envelope(Data(text.utf8))
    }
    public func mainRows(_ advanced: [String: ProjectEditJSON], recoveryV2: Bool = false) -> [[String: ProjectEditJSON]] {
        let types = (matrix["types"]?.array ?? []).compactMap(\.object)
        let addons = (matrix["addons"]?.array ?? []).compactMap(\.object)
        let r5 = advanced["outcomeRules"]?.object?["version"] == .number(1) || recoveryV2
        return advanced.keys.sorted().filter { section in
            guard advanced[section]?.object?["enabled"] == .bool(true) else { return false }
            if section == "scan", advanced.keys.contains(where: { other in other != "scan" && advanced[other]?.object?["enabled"] == .bool(true) && types.contains(where: { $0["section"]?.text == other }) }) { return false }
            return r5 ? !["timer", "timeWindow", "leaderboard", "multiplayer", "branch"].contains(section) : !["branch", "random"].contains(section) && !addons.contains(where: { $0["section"]?.text == section })
        }.map { section in
            (r5 ? types + addons : types).first { row in row["section"]?.text == section && (row["mode"] == nil || row["mode"]?.text == (advanced[section]?.object?["mode"]?.text ?? (section == "diceRoll" ? "d6" : ""))) }
                ?? ["key": .string(section), "section": .string(section), "completionProof": .bool(false), "tools": .object([:])]
        }
    }
    public func guideAllowed(_ node: ProjectEditNode, theme: [String: ProjectEditJSON]) -> Bool {
        guard let advanced = try? advanced(node, theme: theme) else { return false }
        return mainRows(advanced).contains { ["qaText", "qaPick", "sort", "match", "classify"].contains($0["key"]?.text ?? "") }
    }
    public func reason(node: ProjectEditNode, theme: [String: ProjectEditJSON], mode: NativeRuntimeStructureAuthorDraft.Mode) -> String? {
        guard let templateID = node.templateID, templateID > 0 else { return nil }
        guard let source = templates[templateID], let advanced = try? advanced(node, theme: theme) else { return "节点玩法未读取，请重试支持矩阵与玩法详情" }
        // Reuse the installed R5 author contract without changing its schema/defaults.
        // The conversion is a read projection; original template/theme bytes are not written.
        if let bytes = try? JSONEncoder().encode(ProjectEditJSON.object(advanced)),
           let value = try? JSONDecoder().decode([String: TemplateAuthoringJSON].self, from: bytes) {
            var projected = TemplateAdvancedDraft(); projected.value = value
            if let issue = TemplateR5Authoring.issues(projected).first { return "请在原玩法编辑器修正结果或工具配置：" + issue.path }
            if advanced["outcomeRules"] != nil, matrix["outcomeRules"]?.object?["nextStepId"] != .string("SETTLED_FEEDBACK"),
               TemplateR5Authoring.rows(projected).contains(where: { $0.value["nextStepId"] != nil }) { return "进入下一段暂未开放" }
        } else { return "节点玩法配置无法读取，请重试" }
        let game = theme["gameplayRuntime"]?.object ?? [:], zero = game["survival"]?.object?["zeroChallenge"]?.object ?? [:]
        let nodeID = node.localMetadata["id"]?.integer
        let challengeIDs = Set([zero["challengeNodeId"]].compactMap { $0?.integer } + (zero["alternativeNodeIds"]?.array ?? []).compactMap(\.integer))
        let challenge = nodeID.map(challengeIDs.contains) == true
        let rules = advanced["interactionRules"]?.object ?? [:], tools = advanced["interactionTools"]?.object ?? [:]
        let linked = ((game["quests"]?.array ?? []) + (game["facilities"]?.array ?? [])).compactMap(\.object).filter { nodeID != nil && ($0["nodeId"]?.integer == nodeID || $0["operationNodeId"]?.integer == nodeID) }
        let vote = (game["plans"]?.array ?? []).contains { nodeID != nil && $0.object?["operationNodeId"]?.integer == nodeID }
        if !mode.shared {
            if ([rules] + linked).contains(where: { ($0["scope"]?.text ?? "OWNER") != "OWNER" || ($0["targetScope"]?.text ?? "OWNER") != "OWNER" }) { return "个人和独立队伍的效果只能作用于本人或本队" }
            if vote || tools["allowTrade"] == .bool(true) || tools["votePolicy"] != nil || tools["decidesEnding"] == .bool(true) || !(tools["plans"]?.array ?? []).isEmpty { return "交易和表决需要队伍共用现场" }
        }
        if !(tools["plans"]?.array ?? []).isEmpty && !Set(rules.keys).isSubset(of: ["resourceSlots"]) { return "表决不能再设置扣费、次数或独立奖励" }
        var rows = mainRows(advanced, recoveryV2: challenge && zero["version"] == .number(2))
        if rows.isEmpty && !challenge {
            let key = matrix["legacyProofs"]?.object?.first { $0.value.integer == source["validationMethod"]?.integer }?.key
            if key == "GPS" { rows = [["key": .string("GPS"), "completionProof": .bool(true)]] }
            else if let key, let row = (matrix["types"]?.array ?? []).first(where: { $0.object?["key"]?.text == key })?.object { rows = [row] }
        }
        if rows.isEmpty { return challenge ? "这种玩法不能用作归零挑战" : "这种玩法暂时无法确认是否完成" }
        let r5 = advanced["outcomeRules"]?.object?["version"] == .number(1)
        for row in rows {
            if challenge {
                let recoveryV2 = zero["version"] == .number(2)
                let sections = ["pricePair", "blindTaste", "check", "diceRoll", "coinFlip", "random", "estimate", "qa", "sort", "match", "classify", "typeIn", "ballShake", "reaction", "quietHold", "shout", "compass", "stopwatch", "countdown"]
                if recoveryV2 && !sections.contains(row["section"]?.text ?? "") { return "此玩法暂不支持归零恢复，请选择其他挑战节点" }
                if !["SUPPORTED", "CHALLENGE_ONLY"].contains(row["tools"]?.object?["zeroChallenge"]?.text ?? "") && !(recoveryV2 && row["r5CompletionProof"] == .bool(true)) { return "这种玩法不能用作归零挑战" }
                if advanced["interactionTools"] != nil || !Set(rules.keys).isSubset(of: ["resourceSlots"]) || !linked.isEmpty { return "归零挑战不能再设置扣费、次数或效果" }
            } else {
                if row[r5 ? "r5CompletionProof" : "completionProof"] != .bool(true) { return "这种玩法暂时无法确认是否完成" }
                if !r5 && ((["qaText", "qaPick"].contains(row["key"]?.text ?? "") && (advanced["qa"]?.object?["maxTries"]?.integer ?? 0) > 0) || (row["key"] == .string("sort") && (advanced["sort"]?.object?["maxAttempts"]?.integer ?? 0) > 0)) { return "这里的问答和排序不能限制尝试次数" }
                if row["key"] == .string("scan") && source["validationMethod"] != matrix["legacyProofs"]?.object?["scan"] { return "扫码玩法须选择扫码验证" }
            }
        }
        return nil
    }
}

@MainActor public protocol NativeRuntimeStructureAuthorReading: AnyObject {
    func runtimeStructureInputs(draft: ProjectEditDraft, session: ProjectEditSession) async throws -> NativeRuntimeStructureAuthorInputs
    func runtimeStructureInputsAreCurrent(_ inputs: NativeRuntimeStructureAuthorInputs, session: ProjectEditSession) -> Bool
}
