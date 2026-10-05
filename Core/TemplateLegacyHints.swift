import Foundation

public enum TemplateLegacyHintField: String, CaseIterable, Identifiable {
    case hint1, hint2, answerReveal
    public var id: String { rawValue }
    public var draftPath: WritableKeyPath<TemplateAuthoringDraft, String?> {
        switch self { case .hint1: return \.hint1; case .hint2: return \.hint2; case .answerReveal: return \.answerReveal }
    }
}

public extension TemplateAuthoringMethod {
    var supportsLegacyHints: Bool { self == .text || self == .choice || self == .gps }
}

public extension TemplateAuthoringDraft {
    /// The mini hydrates using string presence, not trimmed content. Reading never migrates storage.
    var legacyHintsAreEnabled: Bool {
        legacyHintsEnabled ?? [hint1, hint2, answerReveal].contains { !($0 ?? "").isEmpty }
    }
    var legacyHintControlsVisible: Bool {
        finishEnabled && validationMethod.supportsLegacyHints && !advanced.hasLegacyHintPrimaryGame
    }
    /// Only the deliberate off action clears all three fields. Method changes merely suppress them.
    @discardableResult mutating func setLegacyHintsEnabled(_ enabled: Bool) -> Bool {
        guard legacyHintControlsVisible else { return false }
        legacyHintsEnabled = enabled
        if !enabled { hint1 = ""; hint2 = ""; answerReveal = "" }
        return true
    }
    @discardableResult mutating func setLegacyHint(_ field: TemplateLegacyHintField, to text: String) -> Bool {
        guard legacyHintControlsVisible, legacyHintsAreEnabled else { return false }
        self[keyPath: field.draftPath] = text
        return true
    }
}

public extension TemplateAdvancedDraft {
    /// Read-only projection of recognized primary game configurations for hint visibility.
    /// Do not reuse gameSections/enabledGames: modifiers and recognized primary games differ.
    /// This hides only legacy editing; it neither selects a game nor disables any siblings.
    var hasLegacyHintPrimaryGame: Bool {
        let primarySections = ["album", "branch", "sort", "match", "classify", "estimate", "pricePair",
            "hiddenObject", "predict", "random", "profile", "note", "photoCheck", "steps", "reaction",
            "ballShake", "quietHold", "compass", "shout", "countdown", "stopwatch", "check", "typeIn",
            "coinFlip", "scan"]
        func active(_ section: String) -> Bool { value[section]?.object?["enabled"]?.legacyHintJavaScriptTruthy ?? false }
        if primarySections.contains(where: active) { return true }
        if active("qa"), let mode = value["qa"]?.object?["mode"]?.string, ["TYPE", "PICK", "SHOT"].contains(mode) { return true }
        // The mini defaults missing/empty dice mode to d6, but leaves unknown modes unrecognized.
        if active("diceRoll") {
            let mode = value["diceRoll"]?.object?["mode"]
            if !(mode?.legacyHintJavaScriptTruthy ?? false) { return true }
            if let text = mode?.string, ["d6", "d20"].contains(text) { return true }
        }
        return false
    }
}

private extension TemplateAuthoringJSON {
    /// Read-only compatibility for historical, non-normalized JSON values.
    var legacyHintJavaScriptTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let value): return value
        case .string(let value): return !value.isEmpty
        case .number(let value): return value != 0 && !value.isNaN
        case .array, .object: return true
        }
    }
}
