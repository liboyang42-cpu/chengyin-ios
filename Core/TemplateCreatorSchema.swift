import Foundation

/// Contract-specific controls, rather than an untyped JSON editor. Identifiers and
/// enum values are wire values; labels are localization keys only.
public enum TemplateCreatorFamily: String, CaseIterable, Codable, Identifiable {
    case random, branch, leaderboard, multiplayer, timeWindow, blindTaste, silentOrder, diyName
    case musicCorner, steps, dailySign, slowTask, estimate, pricePair, hiddenObject, predict, qa, scan
    case album, profile, photoCheck, check, note, typeIn
    public var id: String { rawValue }
    public var labelKey: String { "creator.family." + rawValue }
    public var providerKey: String {
        switch self {
        case .steps: return "creator.provider.wechatSteps"
        case .scan: return "creator.provider.scan"
        case .photoCheck: return "creator.provider.vision"
        case .timeWindow, .slowTask, .predict, .dailySign: return "creator.provider.serverClock"
        case .multiplayer, .leaderboard, .note, .profile, .check: return "creator.provider.serverState"
        case .musicCorner: return "creator.provider.music"
        default: return "creator.provider.local"
        }
    }
    public var fullscreenOnly: Bool { [.steps, .scan, .blindTaste, .hiddenObject].contains(self) }
}
public struct TemplateCreatorField: Identifiable {
    public indirect enum Kind {
        case text(max: Int, required: Bool, pattern: String?)
        case number(min: Double, max: Double, integer: Bool)
        case choice([String]), toggle, stateValue
        case object([TemplateCreatorField])
        case rows([TemplateCreatorField], min: Int, max: Int, identity: String?)
        case strings(min: Int, max: Int, length: Int), poems
    }
    public let id: String
    public let kind: Kind
    public let initial: TemplateAuthoringJSON
    public var labelKey: String { "creator.field." + id }
    public init(_ id: String, _ kind: Kind, _ initial: TemplateAuthoringJSON) { self.id = id; self.kind = kind; self.initial = initial }
}
public enum TemplateCreatorSchema {
    public typealias Field = TemplateCreatorField
    public static let keyPattern = "^[A-Za-z0-9_-]{1,64}$"
    static func t(_ key: String, _ max: Int, _ required: Bool = false, _ initial: String = "", pattern: String? = nil) -> Field {
        .init(key, .text(max: max, required: required, pattern: pattern), .string(initial))
    }
    static func n(_ key: String, _ min: Double, _ max: Double, _ initial: Double, integer: Bool = true) -> Field {
        .init(key, .number(min: min, max: max, integer: integer), .number(initial))
    }
    static func b(_ key: String, _ initial: Bool = false) -> Field { .init(key, .toggle, .bool(initial)) }
    static func c(_ key: String, _ choices: [String], _ initial: String) -> Field { .init(key, .choice(choices), .string(initial)) }
    static func o(_ key: String, _ fields: [Field]) -> Field { .init(key, .object(fields), .object(defaults(fields))) }
    static func a(_ key: String, _ fields: [Field], _ min: Int, _ max: Int, identity: String? = nil, count: Int = 0) -> Field {
        let rows: [TemplateAuthoringJSON] = (0..<count).map { index in
            var row = defaults(fields)
            if let identity { row[identity] = .string("\(key)_\(index + 1)") }
            return .object(row)
        }
        return .init(key, .rows(fields, min: min, max: max, identity: identity), .array(rows))
    }
    static func s(_ key: String, _ min: Int, _ max: Int, _ length: Int) -> Field { .init(key, .strings(min: min, max: max, length: length), .array([])) }
    static func id(_ key: String = "id") -> Field { t(key, 64, true, pattern: keyPattern) }
    static func xp(_ max: Double = 1000) -> Field { n("xp", 0, max, 0) }
    static func media(_ key: String, _ max: Int = 512, required: Bool = false) -> Field { t(key, max, required) }
    public static func defaults(_ fields: [Field]) -> [String: TemplateAuthoringJSON] { Dictionary(uniqueKeysWithValues: fields.filter { $0.initial != .null }.map { ($0.id, $0.initial) }) }
    public static var effects: [Field] { [c("op", ["SET", "INC", "ADD_TAG"], "INC"), t("var", 64), .init("value", .stateValue, .number(1))] }
    public static var condition: [Field] { [c("op", ["EQ", "NE", "GT", "GTE", "LT", "LTE", "HAS_TAG", "NODE_COMPLETED"], "GTE"), t("var", 64), .init("value", .stateValue, .number(1)), n("nodeId", 1, 9007199254740991, 1)] }
    static func effectList(_ key: String) -> Field { a(key, effects, 0, 16) }
    public static func fields(_ family: TemplateCreatorFamily) -> [Field] {
        switch family {
        case .random:
            return [t("deckName", 20), n("drawCount", 1, 50, 1), a("items", [id(), t("label", 40, true), n("weight", 1, 100000, 1), t("content", 500), media("audioUrl", 500)], 1, 50, identity: "id", count: 1)]
        case .branch:
            return [t("startStepId", 64, true, "start", pattern: keyPattern), a("steps", [id(), t("title", 80), t("body", 1000), b("terminal", true), t("outcomeCode", 64, false, "COMPLETED", pattern: keyPattern), t("outcomeLabel", 80), a("options", [id(), t("label", 80, true), id("nextStepId"), n("score", -100000, 100000, 0), effectList("effects")], 0, 12, identity: "id")], 1, 50, identity: "id", count: 1)]
        case .leaderboard:
            return [c("metric", ["ELAPSED_TIME", "SCORE", "COMPLETED_UNITS"], "ELAPSED_TIME"), c("scope", ["ACTIVITY", "TOPIC"], "ACTIVITY"), n("limit", 1, 100, 50)]
        case .multiplayer:
            return [c("mode", ["SEQUENTIAL", "ROLE_BASED"], "SEQUENTIAL"), n("minPlayers", 2, 20, 2), n("maxPlayers", 2, 20, 4), c("assignment", ["AUTO", "LEADER"], "AUTO"), n("requiredTurns", 1, 1000, 1), n("unitScore", 0, 100000, 0), a("roles", [id(), t("label", 40, true), n("min", 0, 20, 1), n("max", 1, 20, 4)], 1, 20, identity: "id", count: 1), s("turnOrder", 1, 100, 64)]
        case .timeWindow:
            return [t("eyebrow", 32), t("title", 32), t("openFrom", 5, true, "20:00", pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$"), t("openTo", 5, true, "23:00", pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$"), t("subscribeTmplId", 64)]
        case .blindTaste:
            return [t("title", 64, true), t("steps", 120), t("hint", 60), xp(), id("answerKey"), a("options", [id("key"), t("label", 32, true)], 2, 6, identity: "key", count: 2)]
        case .silentOrder: return [t("title", 64, true), t("rule", 200), n("limitSeconds", 0, 3600, 0)]
        case .diyName: return [t("title", 64, true), n("maxLength", 2, 40, 16), s("suggestions", 0, 6, 40)]
        case .musicCorner: return [t("title", 64, true), t("trackName", 40), media("audioUrl"), n("durationSeconds", 0, 3600, 0)]
        case .steps: return [t("eyebrow", 32), n("goal", 100, 100000, 6000), xp()]
        case .dailySign: return [t("signer", 16), t("sealText", 8), .init("poems", .poems, .array([]))]
        case .slowTask: return [t("title", 64, true), t("startLabel", 24), t("waitHint", 60), t("unlockLabel", 24), t("unlockText", 200, true), n("waitDays", 1, 7, 1), xp()]
        case .estimate: return [t("title", 64, true), t("unit", 8), t("reveal", 200), n("min", -Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, 0, integer: false), n("max", -Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, 1000, integer: false), n("answer", -Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, 500, integer: false), n("tolerance", 0, 500000, 50, integer: false), xp()]
        case .pricePair: return [t("title", 64, true), xp(200), n("maxTries", 0, 10, 0), a("items", [id(), t("name", 32, true), media("imageUrl"), b("correct")], 3, 8, identity: "id", count: 3)]
        case .hiddenObject: return [t("title", 64, true), t("hint", 60), media("imageUrl", required: true), xp(), n("maxTries", 0, 10, 0), a("hotspots", [id(), t("label", 24, true), n("x", 0, 1, 0.5, integer: false), n("y", 0, 1, 0.5, integer: false), n("r", 0.03, 0.15, 0.08, integer: false)], 3, 5, identity: "id", count: 3)]
        case .predict: return [t("question", 120, true), t("hint", 60), n("closeAtHour", 0, 23, 20), n("revealDays", 0, 30, 1), n("revealHour", 0, 23, 20), xp(), a("options", [id("key"), t("label", 32, true)], 2, 4, identity: "key", count: 2)]
        case .qa: return [c("mode", ["TYPE", "PICK", "SHOT"], "TYPE"), t("title", 120, true), t("lead", 60), media("imageUrl"), media("audioUrl"), t("answerText", 200), b("reveal"), t("shotNote", 56), n("maxTries", 0, 10, 0), xp(200), b("multi"), a("options", [id(), t("label", 32, true), t("fb", 120), b("correct"), effectList("effects")], 2, 4, identity: "id", count: 2)]
        case .scan: return [c("kind", ["TEXT", "VOICE", "IMAGE", "OVERLAY"], "TEXT"), t("reply", 200), media("audioUrl"), media("imageUrl"), media("overlayUrl"), n("overlayScale", 20, 100, 60), c("arMode", ["NONE", "PLANE", "MARKER"], "NONE"), media("markerUrl"), media("modelUrl"), xp(200)]
        case .album: return [a("images", [media("url", 1024, required: true), t("line", 40)], 1, 6)]
        case .profile:
            let option = [id("key"), t("label", 32, true), effectList("effects")]
            let override = Field("override", .object([a("requires", condition, 1, 16), t("option", 64), t("voice", 120)]), .null)
            return [t("title", 64), t("lead", 200), o("avatar", [b("enabled", true), b("required")]), a("questions", [t("key", 16, true, "name", pattern: "^[A-Za-z][A-Za-z0-9_]{0,15}$"), t("label", 40, true), c("kind", ["text", "pick"], "text"), n("maxLength", 1, 40, 12), b("required", true), a("options", option, 2, 6, identity: "key"), override], 1, 8, identity: "key", count: 1), xp()]
        case .photoCheck: return [t("title", 64, true), t("shotNote", 120), t("requirement", 60, true), n("minConfidence", 0, 100, 60), n("maxTries", 1, 10, 3), c("fallback", ["retake", "pass"], "retake"), xp(), media("frameUrl", 512), n("frameOpacity", 0, 100, 40), c("mode", ["", "CARD"], ""), t("cardTitle", 64), c("cardStyle", ["", "foil", "plain"], "foil")]
        case .check: return [id("checkId"), c("tier", ["easy", "medium", "hard"], "medium"), t("skill", 200), t("successText", 200), t("failText", 200), effectList("successEffects"), effectList("failEffects"), effectList("critEffects"), effectList("fumbleEffects"), a("advantageIf", condition, 0, 16), a("disadvantageIf", condition, 0, 16), a("mods", [o("when", condition), n("value", -99, 99, 1), t("label", 200)], 0, 16), t("failCostTag", 64)]
        case .note: return [t("title", 64, true), t("prompt", 120, true), n("maxLength", 1, 40, 40), s("presets", 0, 6, 40), n("showPrevious", 0, 5, 3), xp()]
        case .typeIn: return [t("title", 64, true), t("target", 40, true), n("seconds", 3, 120, 10), b("caseSensitive"), n("tries", 0, 10, 0), xp(), b("terminalSkin")]
        }
    }
}
