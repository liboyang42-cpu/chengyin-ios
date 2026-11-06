import Foundation

/// Display-only adapter. Never writes policy keys, user reply bytes, or legacy values.
struct NativeZeroHPAuthorPresentation {
    let locale: Locale
    func text(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "ZeroHPAuthor", locale: locale))
    }
    func completionHint(readOnly: Bool) -> String {
        text(readOnly ? "zeroHP.readOnlyDoneHint" : "zeroHP.doneHint")
    }
    func format(_ key: String, _ values: String...) -> String {
        String(format: text(key), locale: locale, arguments: values.map { $0 as CVarArg })
    }
    static let keys: [String: String] = [
        "生命值域 · 归零后": "zeroHP.copy.000",
        "编辑生命归零策略": "zeroHP.copy.001",
        "挑战／等待、恢复值与次数上限、耗尽后策略及归零回复": "zeroHP.copy.002",
        "生命开关与上限沿用原值域配置；这里不执行挑战、不恢复生命或发奖。": "zeroHP.copy.003",
        "当前项目不可完整编辑，请返回原项目读取权限与版本。": "zeroHP.copy.004",
        "原归零配置无法安全编辑；已保留原文，未替换为默认配置。": "zeroHP.copy.005",
        "支持矩阵或已绑定玩法详情未读取。只读适配未配置、权限变化或网络失败时不能假定支持；可重试，副本尚未写回。": "zeroHP.copy.006",
        "当前选择不符合原配置约束；副本未改变。请查看该字段的原因。": "zeroHP.copy.007",
        "请先保存本主题服务器草稿并回读，再选择真实挑战节点": "zeroHP.copy.008",
        "支持矩阵或已绑定玩法版本已变化，已读取新版本；请核对提示后再完成。": "zeroHP.copy.009",
        "原本地保存未确认；已保留归零策略与挑战副本，请重试本地保存。尚未保存服务器或发布。": "zeroHP.copy.010",
        "权限、玩法版本或引用未能确认，未覆盖原草稿。请重试读取；服务器保存尚未发起。": "zeroHP.copy.011",
        "先编辑副本，完成后沿原保存器持久保存整份本地草稿；本地保存失败会保留副本。退出或返回放弃未确认副本，之后仍须在原项目保存服务器草稿／发布。": "zeroHP.copy.012",
        "正在读取支持矩阵与已绑定玩法": "zeroHP.copy.013",
        "项目、账号、权限、版本或编辑实例已变化，旧副本不能写回。": "zeroHP.copy.014",
        "重新读取本项目": "zeroHP.copy.015",
        "重试支持矩阵与玩法详情": "zeroHP.copy.016",
        "值域": "zeroHP.copy.017",
        "未开启；仅禁止扣该值的任务不会启用生命": "zeroHP.copy.018",
        "兼容配置 · 只读": "zeroHP.copy.019",
        "旧版 BLOCK_PAID／LEGACY_END／旧挑战、原生端未支持的步数恢复及未知版本原样保留；退出与完成都不改写原配置。": "zeroHP.copy.020",
        "恢复到：": "zeroHP.copy.021",
        "最多恢复次数：": "zeroHP.copy.022",
        "次数用完后：": "zeroHP.copy.023",
        "微信运动证明未在原生端开放；本机步数不是等价证明，不能启用或修改此恢复项。": "zeroHP.copy.024",
        "归零时回复": "zeroHP.copy.025",
        "回复内容（最多 2000 字）": "zeroHP.copy.026",
        "可留空；不会覆盖普通节点的通过／没通过回复。": "zeroHP.copy.027",
        "请修正后完成": "zeroHP.copy.028",
        "未取得当前支持矩阵，不能替换为默认配置。原草稿及未完成请求保持不变。": "zeroHP.copy.029",
        "生命归零后": "zeroHP.copy.030",
        "退出": "zeroHP.copy.031",
        "完成": "zeroHP.copy.032",
        "归零后": "zeroHP.copy.033",
        "真实恢复挑战节点": "zeroHP.copy.034",
        "从本主题已保存节点的已绑定玩法选择，不创建临时模板。挑战不扣费、不发普通奖励、不推进章节；完成后沿原章节同步排除主／备挑战节点。": "zeroHP.copy.035",
        "请先保存主题和挑战节点，并回读服务器草稿，再返回选择。": "zeroHP.copy.036",
        "主挑战": "zeroHP.copy.037",
        "恢复玩法：": "zeroHP.copy.038",
        "未选择": "zeroHP.copy.039",
        "未绑定": "zeroHP.copy.040",
        " · 可以移除": "zeroHP.copy.041",
        "可作答的题目类备选": "zeroHP.copy.042",
        "需完成次数（1–99）": "zeroHP.copy.043",
        "限时秒数（1–86400）": "zeroHP.copy.044",
        "恢复条件与耗尽后": "zeroHP.copy.045",
        "等待分钟（1–10080）": "zeroHP.copy.046",
        "恢复步数（1–100000）": "zeroHP.copy.047",
        "原规则以归零后第一次同步的微信运动步数为起点。原生端不以本地传感器替代；此选项不可启用。": "zeroHP.copy.048",
        "最多恢复次数（1–99）": "zeroHP.copy.049",
        "次数用完后": "zeroHP.copy.050",
        "请选择": "zeroHP.copy.051",
        "主题失败": "zeroHP.copy.052",
        "仅禁止扣该值的任务": "zeroHP.copy.053",
        "完成恢复挑战": "zeroHP.copy.054",
        "走够步数": "zeroHP.copy.055",
        "等待一段时间": "zeroHP.copy.056",
        "第一章初始状态": "zeroHP.copy.057",
        "原 RPG 数值资源": "zeroHP.copy.058",
        "生命值": "zeroHP.copy.059",
        "禁止所有收费动作": "zeroHP.copy.060",
        "旧版结束": "zeroHP.copy.061",
        "请先保存全部节点，并在进行方式与节点引导中修正章节关系后再完成": "zeroHP.copy.062",
        "请配置所选恢复条件": "zeroHP.copy.063",
        "只能设置所选的恢复项；请重新选择归零策略后完成": "zeroHP.copy.064",
        "归零时回复不能超过 2000 字": "zeroHP.copy.065",
        "请选择有效的 HP 归零策略": "zeroHP.copy.066",
        "原 schema2 HP 声明未明确，请先在原 RPG 数值资源编辑器确认；不代填默认值": "zeroHP.copy.067",
        "生命值域无法读取，请在原值域编辑器检查": "zeroHP.copy.068",
        "恢复配置版本不受支持": "zeroHP.copy.069",
        "恢复值": "zeroHP.copy.070",
        "请先修正生命值上限": "zeroHP.copy.071",
        "最多恢复次数": "zeroHP.copy.072",
        "请选择次数用完后的策略": "zeroHP.copy.073",
        "等待分钟": "zeroHP.copy.074",
        "恢复步数": "zeroHP.copy.075",
        "需完成次数": "zeroHP.copy.076",
        "恢复挑战限时（秒）": "zeroHP.copy.077",
        "已保存节点身份重复，请重新读取原草稿": "zeroHP.copy.078",
        "请先保存主题和挑战节点，再选择主挑战": "zeroHP.copy.079",
        "备选挑战最多 3 个，不能重复，须为本主题其他真实节点": "zeroHP.copy.080",
        "微信运动步数恢复未在原生端开放；不能使用本机步数代替证明。已有配置保留，需改为支持的策略后才能完成修改。": "zeroHP.copy.081",
        "当前主题的玩法支持信息未就绪，请重试读取": "zeroHP.copy.082",
        "当前主题不支持此归零策略；请先核对进行方式与原玩法配置": "zeroHP.copy.083",
        "请先保存真实节点并绑定可读取的原玩法模板": "zeroHP.copy.084",
        "这种玩法不能用作归零挑战": "zeroHP.copy.085",
        "原玩法配置无法读取，请重试": "zeroHP.copy.086",
        "进入下一段暂未开放": "zeroHP.copy.087",
        "归零挑战不能配置普通结果费用或奖励；请在原玩法中修正": "zeroHP.copy.088",
        "归零挑战不能同时配置普通任务、设施、扣费、次数或效果；请选择专用挑战节点": "zeroHP.copy.089",
        "个人或独立队伍的挑战不能绑定跨队表决": "zeroHP.copy.090",
        "此玩法暂不支持归零恢复，请选择其他挑战节点": "zeroHP.copy.091",
        "这种玩法没有归零挑战恢复支持": "zeroHP.copy.092",
        "检定恢复须先在原玩法中配置通过／没通过之后": "zeroHP.copy.093",
        "恢复玩法须匹配主挑战节点，请重新选择主挑战": "zeroHP.copy.094",
        "检定恢复须先配置通过／没通过之后": "zeroHP.copy.095",
        "体能或传感器主挑战须配置至少一个可作答的题目类备选；挑战不扣费、不发普通奖励、不推进章节": "zeroHP.copy.096",
        "hp含原资源合同之外字段；不会删除它们。": "zeroHP.hpExtra",
        "hp启用配置须为明确布尔值。": "zeroHP.hpBoolean",
        "hp初始值须为非负整数。": "zeroHP.hpInitial",
        "hp初始值不能超过该资源上限。": "zeroHP.hpMaximum",
        "hp本次编辑须明确启用状态、上限和初始值；不代填默认值。": "zeroHP.hpExplicit",
    ]
    func message(_ original: String) -> String {
        if let key = Self.keys[original] { return text(key) }
        let prefix = "请先在原玩法编辑器修正结果或工具配置："
        if original.hasPrefix(prefix) { return format("zeroHP.fixPath", String(original.dropFirst(prefix.count))) }
        // Match the known diagnostic suffix, not colons inside an author's node name.
        for source in Self.keys.keys.sorted(by: { $0.count > $1.count }) where original.hasSuffix("：" + source) {
            return String(original.dropLast(source.count + 1)) + ": " + message(source)
        }
        if let range = original.range(of: "：" + prefix, options: .backwards) {
            return String(original[..<range.lowerBound]) + ": " + format("zeroHP.fixPath", String(original[range.upperBound...]))
        }
        if let captures = captures(original, pattern: "^(.+)须为 ([0-9]+) 至 ([0-9]+) 的整数$") {
            return format("zeroHP.integerRange", message(captures[0]), captures[1], captures[2])
        }
        if let values = captures(original, pattern: "^节点 ([0-9]+) 已删除或未保存，请重新选择$") { return format("zeroHP.nodeGone", values[0]) }
        if let values = captures(original, pattern: "^hp上限须为([0-9]+)–([0-9]+)整数。$") { return format("zeroHP.hpRange", values[0], values[1]) }
        for editor in ["第一章初始状态", "原 RPG 数值资源"] {
            let prefix = "请先在" + editor + "开启"
            if original.hasPrefix(prefix) {
                let name = String(original.dropFirst(prefix.count))
                // English argument order is deliberately handled without altering the user name.
                if locale.language.languageCode?.identifier == "en" { return format("zeroHP.enableEnglish", name, message(editor)) }
                return original
            }
        }
        // Retain unknown details verbatim. An unknown diagnostic never authorizes editing.
        return original
    }
    private func captures(_ value: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: value).map { String(value[$0]) } }
    }
    func gameplay(_ raw: String) -> String {
        guard NativeZeroHPAuthorPolicy.challengeSections.contains(raw) else { return raw }
        return text("zeroHP.gameplay." + raw)
    }
    func healthName(_ draft: NativeZeroHPAuthorDraft) -> String {
        draft.theme["hpName"]?.text ?? message("生命值")
    }
    func compatibility(_ draft: NativeZeroHPAuthorDraft) -> String {
        let name: String
        if let policy = draft.selected { name = message(policy.title) }
        else if draft.policy == "BLOCK_PAID" { name = message("禁止所有收费动作") }
        else if draft.policy == "LEGACY_END" { name = message("旧版结束") }
        else { name = draft.policy }
        let row = draft.blocks[draft.selected?.blockKey ?? ""] ?? [:]
        let quantity: String?
        switch draft.selected {
        case .some(.challenge): quantity = row["challengeNodeId"]?.integer.map { format("zeroHP.node", String($0)) }
        case .some(.wait): quantity = row["minutes"]?.integer.map { format("zeroHP.minutes", String($0)) }
        case .some(.steps): quantity = row["steps"]?.integer.map { format("zeroHP.steps", String($0)) }
        default: quantity = nil
        }
        return [name, quantity, draft.zeroMessage.isEmpty ? nil : draft.zeroMessage].compactMap { $0 }.joined(separator: " · ")
    }
}
