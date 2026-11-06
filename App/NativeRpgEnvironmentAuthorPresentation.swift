import Foundation

/// Display only. The original three switches and captured review bytes remain unchanged.
struct NativeRpgEnvironmentAuthorPresentation {
    let locale: Locale
    func text(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "RpgEnvironmentAuthor", locale: locale))
    }
    static let keys: [String: String] = [
        "须已有原 schema2 规则；不覆盖缺失、旧版或未识别配置。": "rpgEnvironment.copy.000",
        "请按原合同明确配置；未写回。": "rpgEnvironment.copy.001",
        "配置未变，保留原字节；没有新增保存或发布。": "rpgEnvironment.copy.002",
        "原完整本地草稿保存未确认；编辑和预览保留，可重试本地保存。尚未保存服务器或发布。": "rpgEnvironment.copy.003",
        "原保存器已保存完整本地草稿，尚未保存服务器或发布。": "rpgEnvironment.copy.004",
        "原项目或配置已变化，未覆盖。": "rpgEnvironment.copy.005",
        "原 RPG 环境与地点": "rpgEnvironment.copy.006",
        "读取本主题原环境配置": "rpgEnvironment.copy.007",
        "项目或会话已变化，请关闭重开。": "rpgEnvironment.copy.008",
        "启用环境与服务端时段": "rpgEnvironment.copy.009",
        "明确允许模板剧本天气覆盖": "rpgEnvironment.copy.010",
        "启用原节点地点事实": "rpgEnvironment.copy.011",
        "明确保留当前三个开关": "rpgEnvironment.copy.012",
        "剧本天气不是实时观测；仅在环境与作者覆盖同时开启时生效。地点仅消费明确的冻结节点室内/户外，不从场馆名字推断。天气供应商、海拔和服务端距离缺源仍为未知；不输入玩家坐标或凭据。": "rpgEnvironment.copy.013",
        "本页只声明原三个开关；模板天气与室内配置编辑尚未接入，不提供实时观测或定位授权。仍需原项目保存与发布。": "rpgEnvironment.copy.014",
        "预览原环境配置": "rpgEnvironment.copy.015",
        "重试保存原完整项目草稿": "rpgEnvironment.copy.016",
        "确认保存原完整项目草稿": "rpgEnvironment.copy.017",
        "关闭环境编辑副本": "rpgEnvironment.copy.018",
    ]
    func message(_ source: String) -> String { Self.keys[source].map { text($0) } ?? source }
}
