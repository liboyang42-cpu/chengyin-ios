import Foundation

extension TemplateAdvancedDraft {
    public var legacyVariantIssues: [TemplateRootIssue] {
        var result: [TemplateRootIssue] = []
        func fail(_ path: String, _ code: String) { result.append(.init(path: path, code: code)) }
        let fields: [String: Set<String>] = [
            "coinFlip": ["enabled", "kicker", "xp", "heads", "tails"],
            "diceRoll": ["enabled", "kicker", "xp", "diceCount", "faces", "mode", "dc", "modifier", "rollMode", "successText", "failText"],
            "reaction": ["enabled", "kicker", "xp", "rounds", "goalMs"],
            "ballShake": ["enabled", "kicker", "xp", "goal", "timed", "seconds"],
            "quietHold": ["enabled", "kicker", "xp", "sub", "seconds"],
            "countdown": ["enabled", "kicker", "xp", "seconds", "doneText"],
            "stopwatch": ["enabled", "kicker", "xp", "targetSeconds", "toleranceMs", "tries"]
        ]
        func number(_ section: String, _ key: String, _ min: Double, _ max: Double, defaultValue: Double? = nil) {
            let raw = value[section]?.object?[key]
            guard let n = raw?.number ?? defaultValue, n.isFinite, n.rounded() == n, n >= min, n <= max, !(raw?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? false) else { fail(section + "." + key, "number"); return }
        }
        for (section, known) in fields {
            let object = value[section]?.object ?? [:]
            for key in object.keys where !known.contains(key) { fail(section + "." + key, "unknown") }
            if section == "coinFlip" {
                for side in ["heads", "tails"] { for key in (object[side]?.object ?? [:]).keys where !["label", "action"].contains(key) { fail(section + "." + side + "." + key, "unknown") } }
            }
            guard enabled(section) else { continue }
            number(section, "xp", 0, 1000, defaultValue: 0)
            switch section {
            case "diceRoll":
                if !["d6", "d20"].contains(diceMode) { fail("diceRoll.mode", "mode") }
                if diceMode == "d20" {
                    number(section, "dc", 1, 40); number(section, "modifier", -20, 20)
                    if !["normal", "advantage", "disadvantage"].contains(object["rollMode"]?.string ?? "") { fail("diceRoll.rollMode", "mode") }
                    for key in ["successText", "failText"] {
                        let text = (object[key]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if text.isEmpty || text.utf16.count > 200 { fail("diceRoll." + key, "text") }
                    }
                } else { number(section, "diceCount", 1, 2, defaultValue: 1) }
            case "reaction": number(section, "rounds", 1, 10); number(section, "goalMs", 120, 3000)
            case "ballShake": number(section, "goal", 1, 200); if object["timed"]?.bool == true { number(section, "seconds", 3, 300) }
            case "quietHold": number(section, "seconds", 5, 300)
            case "countdown": number(section, "seconds", 5, 3600)
            case "stopwatch": number(section, "toleranceMs", 50, 5000); number(section, "tries", 0, 10)
            default: break
            }
        }
        if enabled("sort") { number("sort", "maxAttempts", 0, 10, defaultValue: 0) }
        return result
    }
}
public struct TemplateD20Rehearsal: Equatable {
    public let values: [Int]; public let kept: Int; public let total: Int; public let success: Bool; public let text: String
    /// Source-style deterministic creator example, never a server roll or player receipt.
    public init(draft: TemplateAdvancedDraft) throws {
        guard draft.enabled("diceRoll"), draft.diceMode == "d20", draft.legacyVariantIssues.isEmpty else { throw TemplateAuthoringError.invalidDraft }
        let mode = draft.text("diceRoll", "rollMode")
        values = mode == "normal" ? [12] : [12, 7]
        kept = mode == "disadvantage" ? values.min()! : values.max()!
        total = kept + (draft.value["diceRoll"]?.object?["modifier"]?.integer ?? 0)
        success = total >= (draft.value["diceRoll"]?.object?["dc"]?.integer ?? 10)
        text = draft.text("diceRoll", success ? "successText" : "failText")
    }
}
