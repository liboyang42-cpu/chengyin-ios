import Foundation

/// Display only. Original condition rules and captured review bytes are never modified here.
struct NativeRpgConditionAuthorPresentation {
    let locale: Locale
    func text(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "RpgConditionAuthor", locale: locale))
    }
    static let keys: [String: String] = [
        "须已有原 schema2 规则；不覆盖缺失、旧版或未识别配置。": "rpgCondition.copy.000",
        "请按原合同明确配置；未写回。": "rpgCondition.copy.001",
        "配置未变，保留原字节；没有新增保存或发布。": "rpgCondition.copy.002",
        "原完整本地草稿保存未确认；编辑和预览保留，可重试本地保存。尚未保存服务器或发布。": "rpgCondition.copy.003",
        "原保存器已保存完整本地草稿，尚未保存服务器或发布。": "rpgCondition.copy.004",
        "原项目或配置已变化，未覆盖。": "rpgCondition.copy.005",
        "原 RPG 状态规则": "rpgCondition.copy.006",
        "读取本主题原状态配置": "rpgCondition.copy.007",
        "项目或会话已变化，请关闭重开，不能写回旧副本。": "rpgCondition.copy.008",
        "显式启用正式状态（每状态最多2层，总类数5）": "rpgCondition.copy.009",
        "明确保留当前开关并采用正式容量5": "rpgCondition.copy.010",
        "持续沿原正式规则：疲惫3节点，受寒/中暑4，专注1，恐惧/亢奋2；受启发1次主动检定。节点首完才扣持续，GET或重进不扣。休息/成功检定/已知环境沿原事件，不是标签。": "rpgCondition.copy.011",
        "预览原状态规则": "rpgCondition.copy.012",
        "重试保存原完整项目草稿": "rpgCondition.copy.013",
        "确认保存原完整项目草稿": "rpgCondition.copy.014",
        "只写入原 schema2 的状态启用值与正式容量5，仍需原项目保存、请求恢复和发布。模板状态效果编辑尚未接入；本页不改变玩家状态或重置旧局。": "rpgCondition.copy.015",
        "关闭状态编辑副本": "rpgCondition.copy.016",
    ]
    func message(_ source: String) -> String { Self.keys[source].map { text($0) } ?? source }
}
