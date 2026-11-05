import Foundation

/// Projection of fixed58 support-matrix.js and installed r388 validation. Uses the
/// existing private bound-template reader; no public catalog or invented templates.
public enum NativeZeroHPAuthorPolicy {
    // This is the original GameplayRuntimeConfig v2 recovery allowlist, NOT full37.
    public static let challengeSections: Set<String> = ["pricePair", "blindTaste", "check", "diceRoll", "coinFlip", "random", "estimate", "qa", "sort", "match", "classify", "typeIn", "ballShake", "reaction", "quietHold", "shout", "compass", "stopwatch", "countdown"]
    public static func policyKeys(draft: NativeZeroHPAuthorDraft, inputs: NativeRuntimeStructureAuthorInputs) -> [String] {
        let theme = draft.proposedTheme, game = theme["gameplayRuntime"]?.object ?? [:]
        let structured = ["PLAYER", "TEAM"].contains(game["runtimeScope"]?.text ?? "")
            || !(game["acts"]?.array ?? []).isEmpty || !(game["quests"]?.array ?? []).isEmpty
            || (theme["chapters"]?.array ?? []).contains { row in ["completion", "exclusiveGroups", "extraNodes"].contains { row.object?[$0] != nil } }
        var generic = false
        for node in draft.original.chapters.flatMap(\.nodes) where (node.templateID ?? 0) > 0 {
            // An unreadable bound template is unknown, never evidence that the
            // legacy policy list applies. Keep selection and completion blocked.
            guard let advanced = try? inputs.advanced(node, theme: theme) else { return [] }
            if advanced["outcomeRules"] != nil || advanced["interactionTools"] != nil || !Set((advanced["interactionRules"]?.object ?? [:]).keys).isSubset(of: ["resourceSlots"]) { generic = true }
        }
        return (inputs.matrix["zeroHpPolicies"]?.object?[structured || generic ? "generic" : "legacy"]?.array ?? []).compactMap(\.text)
    }
    public static func reason(_ policy: NativeZeroHPAuthorDraft.Policy, draft: NativeZeroHPAuthorDraft, inputs: NativeRuntimeStructureAuthorInputs) -> String? {
        // Server capability is not a native platform proof grant. WeRun remains off.
        if policy == .steps { return "微信运动步数恢复未在原生端开放；不能使用本机步数代替证明。已有配置保留，需改为支持的策略后才能完成修改。" }
        let keys = policyKeys(draft: draft, inputs: inputs)
        if keys.isEmpty { return "当前主题的玩法支持信息未就绪，请重试读取" }
        if !keys.contains(policy.rawValue) { return "当前主题不支持此归零策略；请先核对进行方式与原玩法配置" }
        return nil
    }
    public static func nodeReason(_ node: ProjectEditNode, draft: NativeZeroHPAuthorDraft, inputs: NativeRuntimeStructureAuthorInputs) -> String? {
        guard let id = node.localMetadata["id"]?.integer, id > 0, let templateID = node.templateID, templateID > 0,
              inputs.templates[templateID] != nil, let advanced = try? inputs.advanced(node, theme: draft.theme) else { return "请先保存真实节点并绑定可读取的原玩法模板" }
        let rows = inputs.mainRows(advanced, recoveryV2: true)
        if rows.isEmpty { return "这种玩法不能用作归零挑战" }
        // Preserve the installed R5 outcome validator and source revision projection.
        guard let bytes = try? JSONEncoder().encode(ProjectEditJSON.object(advanced)),
              let value = try? JSONDecoder().decode([String: TemplateAuthoringJSON].self, from: bytes) else { return "原玩法配置无法读取，请重试" }
        var projected = TemplateAdvancedDraft(); projected.value = value
        if let issue = TemplateR5Authoring.issues(projected).first { return "请先在原玩法编辑器修正结果或工具配置：" + issue.path }
        let outcomes = TemplateR5Authoring.rows(projected)
        if advanced["outcomeRules"] != nil, inputs.matrix["outcomeRules"]?.object?["nextStepId"] != .string("SETTLED_FEEDBACK"), outcomes.contains(where: { $0.value["nextStepId"] != nil }) { return "进入下一段暂未开放" }
        // Installed r388 GameplaySupportMatrix prohibits ordinary result charges and
        // rewards in v2 recovery. Reading these rows never deletes R5 author content.
        if outcomes.contains(where: { row in !(row.value["costs"]?.array ?? []).isEmpty || !(row.value["effects"]?.array ?? []).isEmpty }) { return "归零挑战不能配置普通结果费用或奖励；请在原玩法中修正" }
        let rules = advanced["interactionRules"]?.object ?? [:]
        let game = draft.theme["gameplayRuntime"]?.object ?? [:]
        let linked = ((game["quests"]?.array ?? []) + (game["facilities"]?.array ?? [])).contains { row in row.object?["nodeId"]?.integer == id || row.object?["operationNodeId"]?.integer == id }
        if advanced["interactionTools"] != nil || !Set(rules.keys).isSubset(of: ["resourceSlots"]) || linked { return "归零挑战不能同时配置普通任务、设施、扣费、次数或效果；请选择专用挑战节点" }
        let shared = game["runtimeScope"] == .string("TEAM") && game["worldMode"] == .string("WORLD_SHARED")
        if !shared && (game["plans"]?.array ?? []).contains(where: { $0.object?["operationNodeId"]?.integer == id }) { return "个人或独立队伍的挑战不能绑定跨队表决" }
        for row in rows {
            guard let section = row["section"]?.text, challengeSections.contains(section) else { return "此玩法暂不支持归零恢复，请选择其他挑战节点" }
            if !["SUPPORTED", "CHALLENGE_ONLY"].contains(row["tools"]?.object?["zeroChallenge"]?.text ?? "") && row["r5CompletionProof"] != .bool(true) { return "这种玩法没有归零挑战恢复支持" }
            if section == "check" && advanced["outcomeRules"]?.object?["version"] != .number(1) { return "检定恢复须先在原玩法中配置通过／没通过之后" }
        }
        return nil
    }
    public static func answerable(_ node: ProjectEditNode, draft: NativeZeroHPAuthorDraft, inputs: NativeRuntimeStructureAuthorInputs) -> Bool {
        guard nodeReason(node, draft: draft, inputs: inputs) == nil, let advanced = try? inputs.advanced(node, theme: draft.theme) else { return false }
        return inputs.mainRows(advanced).contains { $0["completionProof"] == .bool(true) && $0["key"] != .string("scan") }
    }
    public static func challengeIssues(draft: NativeZeroHPAuthorDraft, inputs: NativeRuntimeStructureAuthorInputs) -> [String] {
        let zero = draft.challenge, ids = [zero["challengeNodeId"]?.integer].compactMap { $0 } + draft.alternatives
        var result: [String] = []
        for id in ids {
            guard let node = draft.savedNodes.first(where: { $0.localMetadata["id"]?.integer == id }) else { result.append("节点 \(id) 已删除或未保存，请重新选择"); continue }
            if let reason = nodeReason(node, draft: draft, inputs: inputs) { result.append((node.name.isEmpty ? "节点 \(id)" : node.name) + "：" + reason) }
        }
        guard let main = draft.savedNodes.first(where: { $0.localMetadata["id"]?.integer == zero["challengeNodeId"]?.integer }),
              let advanced = try? inputs.advanced(main, theme: draft.theme) else { return result }
        let key = zero["gameplayKey"]?.text ?? ""
        if !challengeSections.contains(key) || advanced[key]?.object?["enabled"] != .bool(true) { result.append("恢复玩法须匹配主挑战节点，请重新选择主挑战") }
        if key == "check" && advanced["outcomeRules"]?.object?["version"] != .number(1) { result.append("检定恢复须先配置通过／没通过之后") }
        let sensor = inputs.mainRows(advanced).contains { $0["tools"]?.object?["zeroChallenge"] == .string("CHALLENGE_ONLY") && $0["key"] != .string("typeIn") }
        if sensor && !draft.savedNodes.contains(where: { node in draft.alternatives.contains(node.localMetadata["id"]?.integer ?? 0) && answerable(node, draft: draft, inputs: inputs) }) { result.append("体能或传感器主挑战须配置至少一个可作答的题目类备选；挑战不扣费、不发普通奖励、不推进章节") }
        return result
    }
}
