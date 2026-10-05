import Foundation

public enum TemplateAdvancedGame: String, Codable, CaseIterable, Identifiable {
    case coin, dice, react, shake, quiet, countdown, stopwatch
    case sort, match, classify, compass, shout
    public var id: String { rawValue }
    public var section: String {
        switch self { case .coin: return "coinFlip"; case .dice: return "diceRoll"; case .react: return "reaction"
        case .shake: return "ballShake"; case .quiet: return "quietHold"; case .countdown: return "countdown"; case .stopwatch: return "stopwatch"
        case .sort, .match, .classify, .compass, .shout: return rawValue }
    }
    public var labelKey: String { "templateAuthor.game." + rawValue }
}
/// All 38 active source configuration sections have structured authoring. Unknown
/// extensions survive snapshots and fail closed at network serialization.
public struct TemplateAdvancedDraft: Codable, Equatable {
    public var value: [String: TemplateAuthoringJSON]
    public init() { value = Self.defaults }
    public static let gameSections = ["qa", "branch", "estimate", "pricePair", "hiddenObject", "predict", "random", "steps", "reaction", "ballShake", "quietHold", "countdown", "stopwatch", "coinFlip", "diceRoll", "scan", "sort", "match", "classify", "compare", "compass", "shout"]
    public static let defaults: [String: TemplateAuthoringJSON] = [
        "schemaVersion": .number(1),
        "timer": .object(["enabled": .bool(false), "durationSeconds": .number(300), "timeoutResult": .string("FAILED")]),
        "random": .object(["enabled": .bool(false), "drawCount": .number(1), "items": .array([.object(["id": .string("item_1"), "label": .string("线索卡"), "weight": .number(1), "content": .string("")])])]),
        "branch": .object(["enabled": .bool(false), "startStepId": .string("start"), "steps": .array([.object(["id": .string("start"), "title": .string("起点"), "body": .string(""), "terminal": .bool(true), "outcomeCode": .string("COMPLETED"), "outcomeLabel": .string("完成节点"), "options": .array([])])])]),
        "leaderboard": .object(["enabled": .bool(false), "metric": .string("ELAPSED_TIME"), "scope": .string("ACTIVITY"), "limit": .number(50)]),
        "multiplayer": .object(["enabled": .bool(false), "mode": .string("SEQUENTIAL"), "minPlayers": .number(2), "maxPlayers": .number(4), "assignment": .string("AUTO"), "requiredTurns": .number(1), "unitScore": .number(0), "roles": .array([.object(["id": .string("player"), "label": .string("队员"), "min": .number(1), "max": .number(4)])]), "turnOrder": .array([.string("player")])]),
        "timeWindow": .object(["enabled": .bool(false), "eyebrow": .string(""), "title": .string(""), "openFrom": .string("20:00"), "openTo": .string("23:00"), "subscribeTmplId": .string("")]),
        "blindTaste": .object(["enabled": .bool(false), "title": .string(""), "steps": .string(""), "hint": .string(""), "xp": .number(0), "answerKey": .string("A"), "options": .array([.object(["key": .string("A"), "label": .string("")]), .object(["key": .string("B"), "label": .string("")])])]),
        "silentOrder": .object(["enabled": .bool(false), "title": .string(""), "rule": .string(""), "limitSeconds": .number(0)]),
        "diyName": .object(["enabled": .bool(false), "title": .string(""), "maxLength": .number(16), "suggestions": .array([])]),
        "musicCorner": .object(["enabled": .bool(false), "title": .string(""), "trackName": .string(""), "audioUrl": .string(""), "durationSeconds": .number(0)]),
        "steps": .object(["enabled": .bool(false), "eyebrow": .string(""), "goal": .number(6000), "xp": .number(0)]),
        "dailySign": .object(["enabled": .bool(false), "signer": .string(""), "sealText": .string(""), "poems": .array([])]),
        "estimate": .object(["enabled": .bool(false), "title": .string(""), "unit": .string(""), "reveal": .string(""), "min": .number(0), "max": .number(1000), "answer": .number(500), "tolerance": .number(50), "xp": .number(0)]),
        "pricePair": .object(["enabled": .bool(false), "title": .string(""), "xp": .number(0), "maxTries": .number(0), "items": .array([.object(["id": .string("pic_1"), "name": .string(""), "imageUrl": .string(""), "correct": .bool(true)]), .object(["id": .string("pic_2"), "name": .string(""), "imageUrl": .string(""), "correct": .bool(false)]), .object(["id": .string("pic_3"), "name": .string(""), "imageUrl": .string(""), "correct": .bool(false)])])]),
        "qa": .object(["enabled": .bool(false), "mode": .string("TYPE"), "title": .string(""), "lead": .string(""), "imageUrl": .string(""), "audioUrl": .string(""), "answerText": .string(""), "reveal": .bool(false), "maxTries": .number(0), "xp": .number(0), "options": .array([.object(["id": .string("opt_1"), "label": .string(""), "fb": .string(""), "correct": .bool(true)]), .object(["id": .string("opt_2"), "label": .string(""), "fb": .string(""), "correct": .bool(false)])])]),
        "scan": .object(["enabled": .bool(false), "kind": .string("TEXT"), "reply": .string(""), "audioUrl": .string(""), "imageUrl": .string(""), "xp": .number(0)]),
        "hiddenObject": .object(["enabled": .bool(false), "title": .string(""), "hint": .string(""), "imageUrl": .string(""), "xp": .number(0), "hotspots": .array([.object(["id": .string("spot_1"), "label": .string(""), "x": .number(0.25), "y": .number(0.3), "r": .number(0.08)]), .object(["id": .string("spot_2"), "label": .string(""), "x": .number(0.7), "y": .number(0.45), "r": .number(0.08)]), .object(["id": .string("spot_3"), "label": .string(""), "x": .number(0.45), "y": .number(0.75), "r": .number(0.08)])])]),
        "predict": .object(["enabled": .bool(false), "question": .string(""), "hint": .string(""), "closeAtHour": .number(20), "xp": .number(0), "options": .array([.object(["key": .string("A"), "label": .string("")]), .object(["key": .string("B"), "label": .string("")])])]),
        "coinFlip": .object(["enabled": .bool(false), "kicker": .string(""), "xp": .number(0), "heads": .object(["label": .string("正面"), "action": .string("")]), "tails": .object(["label": .string("反面"), "action": .string("")])]),
        "diceRoll": .object(["enabled": .bool(false), "kicker": .string(""), "diceCount": .number(1), "xp": .number(0), "faces": .array([.string(""), .string(""), .string(""), .string(""), .string(""), .string("")])]),
        "reaction": .object(["enabled": .bool(false), "kicker": .string(""), "rounds": .number(3), "goalMs": .number(320), "xp": .number(0)]),
        "ballShake": .object(["enabled": .bool(false), "kicker": .string(""), "goal": .number(30), "timed": .bool(false), "seconds": .number(12), "xp": .number(0)]),
        "quietHold": .object(["enabled": .bool(false), "kicker": .string(""), "sub": .string(""), "seconds": .number(15), "xp": .number(0)]),
        "countdown": .object(["enabled": .bool(false), "kicker": .string(""), "seconds": .number(90), "doneText": .string(""), "xp": .number(0)]),
        "stopwatch": .object(["enabled": .bool(false), "kicker": .string(""), "targetSeconds": .number(10), "toleranceMs": .number(300), "tries": .number(3), "xp": .number(0)]),
    ].merging(miniGameDefaults) { _, extra in extra }.merging(creatorDefaults) { existing, addition in
        .object((addition.object ?? [:]).merging(existing.object ?? [:]) { _, existing in existing })
    }
    public init(raw: String?) throws {
        self.init()
        guard let raw, !raw.isEmpty else { return }
        let incoming = try JSONDecoder().decode([String: TemplateAuthoringJSON].self, from: Data(raw.utf8))
        guard (incoming["schemaVersion"]?.integer ?? 1) == 1 else { throw TemplateAuthoringError.invalidContract }
        for (key, entry) in incoming where key != "schemaVersion" {
            if key == "present" { value[key] = entry; continue }
            if !Self.defaults.keys.contains(key) { value[key] = entry; continue }
            guard let fields = entry.object else { throw TemplateAuthoringError.invalidContract }
            var base = value[key]?.object ?? [:]; base.merge(fields) { _, new in new }; value[key] = .object(base)
        }
        retainCreatorSecretAbsence(incoming)
        if let blind = incoming["blindTaste"]?.object, blind["answerKey"] == nil { set("blindTaste", "answerKey", .string("")) }
    }
    /// Configuration sections coexist. Display focus must never choose which sections survive.
    public var enabledGames: [TemplateAdvancedGame] { TemplateAdvancedGame.allCases.filter { enabled($0.section) } }
    public var presentationRequiresFullscreen: Bool {
        enabledGames.contains { !$0.allowsInline } || enabledCreatorFamilies.contains { $0.fullscreenOnly }
    }
    public var enabledConfigurationLabelKeys: [String] {
        (enabled("timer") ? ["templateAuthor.timer"] : []) + enabledGames.map(\.labelKey) + enabledCreatorFamilies.map(\.labelKey)
    }
    public func enabled(_ section: String) -> Bool { value[section]?.object?["enabled"]?.bool ?? false }
    public func text(_ section: String, _ field: String) -> String {
        let v = value[section]?.object?[field]
        if let text = v?.string { return text }
        if let n = v?.number { return n.rounded() == n ? String(format: "%.0f", n) : String(n) }
        return ""
    }
    public mutating func set(_ section: String, _ field: String, _ entry: TemplateAuthoringJSON) {
        var fields = value[section]?.object ?? [:]; fields[field] = entry; value[section] = .object(fields)
    }
    public mutating func setGameEnabled(_ game: TemplateAdvancedGame, _ enabled: Bool) {
        // Patch one addressed section only; preserve all siblings and disabled configuration.
        set(game.section, "enabled", .bool(enabled))
    }
    public mutating func setNested(_ section: String, _ side: String, _ field: String, _ text: String) {
        var object = value[section]?.object?[side]?.object ?? [:]; object[field] = .string(text); set(section, side, .object(object))
    }
    public mutating func setFace(_ index: Int, _ text: String) {
        guard (0..<6).contains(index) else { return }
        var faces = value["diceRoll"]?.object?["faces"]?.array ?? []
        while faces.count < 6 { faces.append(.string("")) }; faces[index] = .string(text); set("diceRoll", "faces", .array(faces))
    }
    public var issues: [String] {
        var result: [String] = []
        func issue(_ key: String) { result.append("templateAuthor.validation." + key) }
        func text(_ section: String, _ field: String) -> String { self.text(section, field).trimmingCharacters(in: .whitespacesAndNewlines) }
        func range(_ section: String, _ field: String, _ lower: Double, _ upper: Double, integer: Bool = false) {
            guard let n = value[section]?.object?[field]?.number, n.isFinite, n >= lower, n <= upper, !integer || n.rounded() == n else { issue(section + "." + field); return }
        }
        if value["schemaVersion"]?.integer != 1 { issue("advancedSchema") }
        let supported = Set(TemplateAdvancedGame.allCases.map(\.section) + TemplateCreatorFamily.allCases.map(\.rawValue) + ["timer"])
        for (section, entry) in value where section != "schemaVersion" && section != "present" {
            if (!Self.defaults.keys.contains(section) && !Self.rootCreatorKeys.contains(section)) || (entry.object?["enabled"]?.bool == true && !supported.contains(section) && !Self.rootCreatorKeys.contains(section)) { issue("advancedUnsupported") }
        }
        if value["present"] != nil {
            if !["inline", "fullscreen"].contains(explicitPresentation) { result.append("playkitAuthor.validation.presentation") }
            if explicitPresentation == "inline", presentationRequiresFullscreen { result.append("playkitAuthor.validation.fullscreenOnly") }
        }
        if enabled("timer") { range("timer", "durationSeconds", 10, 86400, integer: true) }
        for game in TemplateAdvancedGame.allCases where enabled(game.section) {
            if game.isMiniProgramAddition { result += miniGameIssues(game); continue }
            if text(game.section, "kicker").utf16.count > 32 { issue("kicker") }
            // Source XP normalization defaults malformed values to zero; native accepts only safe finite values.
            if let n = value[game.section]?.object?["xp"]?.number, !n.isFinite { issue("number") }
            switch game {
            case .coin:
                for side in ["heads", "tails"] {
                    let fields = value[game.section]?.object?[side]?.object ?? [:]
                    let action = (fields["action"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if action.isEmpty || action.utf16.count > 60 { issue("coinAction") }
                    if (fields["label"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 16 { issue("coinLabel") }
                }
            case .dice:
                if diceMode == "d20" { break }
                let faces = value[game.section]?.object?["faces"]?.array ?? []
                if faces.count != 6 || faces.contains(where: { v in let s = (v.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines); return s.isEmpty || s.utf16.count > 60 }) { issue("diceFaces") }
            case .react: range(game.section, "rounds", 1, 10); range(game.section, "goalMs", 120, 3000)
            case .shake:
                range(game.section, "goal", 1, 200)
                if value[game.section]?.object?["timed"]?.bool == true { range(game.section, "seconds", 3, 300) }
            case .quiet: range(game.section, "seconds", 5, 300)
            case .countdown:
                range(game.section, "seconds", 5, 3600)
                let done = text(game.section, "doneText"); if done.isEmpty || done.utf16.count > 60 { issue("countdownText") }
            case .stopwatch: range(game.section, "targetSeconds", 3, 120); range(game.section, "toleranceMs", 50, 5000); range(game.section, "tries", 0, 10)
            case .sort, .match, .classify, .compass, .shout: break
            }
        }
        result += enabledCreatorFamilies.flatMap { creatorIssues($0).map(\.labelKey) }
        result += creatorUnknownIssues.map(\.labelKey)
        result += legacyVariantIssues.map(\.labelKey)
        result += rootCreatorIssues.map(\.labelKey)
        return result
    }
    public func serialize() throws -> String {
        guard issues.isEmpty else { throw TemplateAuthoringError.invalidDraft }
        guard value.keys.contains(where: { enabled($0) }) || hasRootAuthoringConfiguration else { return "" }
        var normalized = self
        for game in TemplateAdvancedGame.allCases where enabled(game.section) {
            let section = game.section
            if game.isMiniProgramAddition { normalized.normalizeMiniGame(game); continue }
            normalized.set(section, "kicker", .string(text(section, "kicker").trimmingCharacters(in: .whitespacesAndNewlines)))
            normalized.set(section, "xp", .number(value[section]?.object?["xp"]?.number ?? 0))
            let numberFields: [TemplateAdvancedGame: [String]] = [.react: ["rounds", "goalMs"], .shake: ["goal"], .quiet: ["seconds"], .countdown: ["seconds"], .stopwatch: ["targetSeconds", "toleranceMs", "tries"]]
            for field in numberFields[game] ?? [] { normalized.set(section, field, .number(value[section]?.object?[field]?.number ?? 0)) }
            if game == .shake {
                var fields = normalized.value[section]?.object ?? [:]
                if fields["timed"]?.bool == true { fields["seconds"] = .number(value[section]?.object?["seconds"]?.number ?? 0) } else { fields.removeValue(forKey: "seconds") }
                normalized.value[section] = .object(fields)
            }
            if game == .quiet {
                let sub = text(section, "sub").trimmingCharacters(in: .whitespacesAndNewlines)
                var fields = normalized.value[section]?.object ?? [:]; fields["sub"] = sub.isEmpty ? nil : .string(sub); normalized.value[section] = .object(fields)
            }
            if game == .countdown { normalized.set(section, "doneText", .string(text(section, "doneText").trimmingCharacters(in: .whitespacesAndNewlines))) }
            if game == .coin {
                for side in ["heads", "tails"] { for field in ["label", "action"] {
                    normalized.setNested(section, side, field, (value[section]?.object?[side]?.object?[field]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                } }
            }
            if game == .dice && diceMode != "d20" {
                normalized.set(section, "diceCount", .number(value[section]?.object?["diceCount"]?.number == 2 ? 2 : 1))
                normalized.set(section, "faces", .array((value[section]?.object?["faces"]?.array ?? []).prefix(6).map { .string(($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }))
            }
        }
        normalized.normalizeCreatorFamilies()
        normalized.normalizeRootAuthoring()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(normalized.value)
        guard data.count <= 65_536 else { throw TemplateAuthoringError.invalidDraft }
        return String(decoding: data, as: UTF8.self)
    }
}
