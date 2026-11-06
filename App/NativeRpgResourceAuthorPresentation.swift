import Foundation

/// Display-only: wire names, review bytes and all mutations remain in the original author flow.
struct NativeRpgResourceAuthorPresentation {
    let locale: Locale
    func text(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "RpgResourceAuthor", locale: locale))
    }
    static let keys: [String: String] = [
        "原v2四资源配置": "rpgResource.copy.000",
        "编辑原HP／士气／幸运／灵感声明": "rpgResource.copy.001",
        "须已有原schema2 journeyRules；不转换schema1、不新建角色或资源模板。": "rpgResource.copy.002",
        "只声明发布后的原资源开关、初始值和上限；不改变当前局余额。空白表示原源未显式声明，改动该资源时必须明确三项，不自动填入默认值。": "rpgResource.copy.003",
        "显式启用状态": "rpgResource.copy.004",
        "未显式声明": "rpgResource.copy.005",
        "启用": "rpgResource.copy.006",
        "关闭": "rpgResource.copy.007",
        "明确初始值 init": "rpgResource.copy.008",
        "明确上限 max": "rpgResource.copy.009",
        "原上限范围1–20；初始值0至上限。": "rpgResource.copy.010",
        "原上限范围0–5；初始值0至上限。": "rpgResource.copy.011",
        "原上限范围0–1000；初始值0至上限。": "rpgResource.copy.012",
        "恢复此资源的原声明": "rpgResource.copy.013",
        "原阶段休整士气保底": "rpgResource.copy.014",
        "可选 stageRestMoraleFloor": "rpgResource.copy.015",
        "留空即不声明士气保底，不会采用默认恢复量。仅明确启用士气的发布版本在原章节阶段休整时执行；不新增休息按钮，不改变旧局冻结规则。": "rpgResource.copy.016",
        "恢复原阶段士气保底声明": "rpgResource.copy.017",
        "预览原四资源配置": "rpgResource.copy.018",
        "字段或原草稿不可用，未生成可确认预览。": "rpgResource.copy.019",
        "确认写回并保存原项目草稿": "rpgResource.copy.020",
        "原本地保存未确认；保留资源编辑副本，可再次确认本地保存，尚未保存服务器或发布。": "rpgResource.copy.021",
        "已沿原保存器保存本地草稿，尚未保存服务器或发布。": "rpgResource.copy.022",
        "沿原项目保存／同请求恢复／发布及真实新局初始化。旧局不补资源、不迁移余额；原消费、技能点、专长及TEAM写端均不改；阶段士气保底只由原STAGE_REST写端使用明确冻结值。": "rpgResource.copy.023",
        "关闭资源编辑副本": "rpgResource.copy.024",
        "项目、草稿或权限已变化；旧资源副本已停用，请重新读取。": "rpgResource.copy.025",
        "原阶段士气保底须为0至明确士气上限的整数；不会代填恢复量。": "rpgResource.copy.026",
        "阶段士气保底需要明确士气上限；不会推定默认上限。": "rpgResource.copy.027",
        "hp含原资源合同之外字段；不会删除它们。": "rpgResource.issue.28",
        "hp启用配置须为明确布尔值。": "rpgResource.issue.29",
        "hp初始值须为非负整数。": "rpgResource.issue.30",
        "hp初始值不能超过该资源上限。": "rpgResource.issue.31",
        "hp本次编辑须明确启用状态、上限和初始值；不代填默认值。": "rpgResource.issue.32",
        "hp上限须为1–20整数。": "rpgResource.issue.33",
        "原recovery.stationEndIfHurt超出hp新上限；保留原值并拒绝预览，不自动改恢复量。": "rpgResource.issue.34",
        "原recovery.stageRestHpFloor超出hp新上限；保留原值并拒绝预览，不自动改恢复量。": "rpgResource.issue.35",
        "原recovery.exhaustRestHp超出hp新上限；保留原值并拒绝预览，不自动改恢复量。": "rpgResource.issue.36",
        "morale含原资源合同之外字段；不会删除它们。": "rpgResource.issue.37",
        "morale启用配置须为明确布尔值。": "rpgResource.issue.38",
        "morale初始值须为非负整数。": "rpgResource.issue.39",
        "morale初始值不能超过该资源上限。": "rpgResource.issue.40",
        "morale本次编辑须明确启用状态、上限和初始值；不代填默认值。": "rpgResource.issue.41",
        "morale上限须为0–1000整数。": "rpgResource.issue.42",
        "原recovery.stageRestMoraleFloor超出morale新上限；保留原值并拒绝预览，不自动改恢复量。": "rpgResource.issue.43",
        "luck含原资源合同之外字段；不会删除它们。": "rpgResource.issue.44",
        "luck启用配置须为明确布尔值。": "rpgResource.issue.45",
        "luck初始值须为非负整数。": "rpgResource.issue.46",
        "luck初始值不能超过该资源上限。": "rpgResource.issue.47",
        "luck本次编辑须明确启用状态、上限和初始值；不代填默认值。": "rpgResource.issue.48",
        "luck上限须为0–5整数。": "rpgResource.issue.49",
        "原recovery.stageRestLuckFloor超出luck新上限；保留原值并拒绝预览，不自动改恢复量。": "rpgResource.issue.50",
        "inspiration含原资源合同之外字段；不会删除它们。": "rpgResource.issue.51",
        "inspiration启用配置须为明确布尔值。": "rpgResource.issue.52",
        "inspiration初始值须为非负整数。": "rpgResource.issue.53",
        "inspiration初始值不能超过该资源上限。": "rpgResource.issue.54",
        "inspiration本次编辑须明确启用状态、上限和初始值；不代填默认值。": "rpgResource.issue.55",
        "inspiration上限须为0–1000整数。": "rpgResource.issue.56",
    ]
    func message(_ value: String) -> String { Self.keys[value].map { text($0) } ?? value }
    func resource(_ wire: String) -> String {
        guard NativeRpgResourceAuthorDraft.names.contains(wire) else { return wire }
        return text("rpgResource.name." + wire)
    }
}
