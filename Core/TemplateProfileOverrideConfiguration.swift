import Foundation

/// Guided P036 kaccha form over the existing backend override shape; never executes it.
public struct TemplateProfileOverrideConfiguration: Equatable {
    public struct Form: Equatable {
        public var enabled: Bool
        public var variable: String
        public var threshold: String
        public var option: String
        public var voice: String
        public init(enabled: Bool = false, variable: String = "counter.instability", threshold: String = "4", option: String = "", voice: String = "") {
            self.enabled = enabled; self.variable = variable; self.threshold = threshold; self.option = option; self.voice = voice
        }
    }
    public struct Option: Identifiable, Equatable {
        public let key: String
        public let label: String
        public var id: String { key }
    }
    public let questionKey: String
    public let questionLabel: String
    public let options: [Option]
    public let initialForm: Form
    public let isSupported: Bool
    public let canEdit: Bool
    private let source: Data?
    private let index: Int?

    public init(_ draft: TemplateAuthoringDraft, questionKey: String) {
        self.questionKey = questionKey
        let encoded = Self.snapshot(draft), profile = draft.advanced.value["profile"]?.object
        let composition = TemplateProfileQuestionComposition(draft.advanced)
        let selected = composition.questions.firstIndex { $0.key == questionKey }
        let question = selected.flatMap { (profile?["questions"]?.array)?[$0].object }
        let items = selected.map { composition.questions[$0].options.map { Option(key: $0.key, label: $0.label) } } ?? []
        let enabledShape: Bool
        if case .bool? = profile?["enabled"] { enabledShape = true } else { enabledShape = false }
        let parsed = Self.readForm(question?["override"], firstOption: items.first?.key ?? "")
        let supported = encoded != nil && composition.isSupported && enabledShape && selected != nil &&
            question?["kind"]?.string == "pick" && (2...6).contains(items.count) && parsed.supported
        source = encoded; index = selected; options = items; initialForm = parsed.form
        questionLabel = question?["label"]?.string ?? questionKey; isSupported = supported
        if case .bool(true)? = profile?["enabled"] { canEdit = supported } else { canEdit = false }
    }
    public func isCurrent(_ draft: TemplateAuthoringDraft) -> Bool { source != nil && source == Self.snapshot(draft) }
    public func toggling(_ form: Form, enabled: Bool) -> Form {
        var next = form; next.enabled = enabled
        if next.option.isEmpty { next.option = options.first?.key ?? "" }
        return next
    }
    public func issueKeys(_ form: Form) -> [String] {
        guard isSupported else { return ["templateProfileOverride.readOnly"] }
        guard canEdit else { return ["templateProfileOverride.disabled"] }
        guard form.enabled else { return [] }
        var issues: [String] = []
        let variable = Self.trim(form.variable), option = Self.trim(form.option)
        if variable.range(of: "^(clue|relation|counter)\\.[a-z][a-z0-9_]{0,47}$", options: .regularExpression) == nil { issues.append("templateProfileOverride.variableInvalid") }
        if let number = Self.number(form.threshold), number.rounded() == number, (-99...99).contains(number) {} else { issues.append("templateProfileOverride.thresholdInvalid") }
        if !options.contains(where: { $0.key == option }) { issues.append("templateProfileOverride.optionInvalid") }
        if Self.trim(form.voice).utf16.count > 120 { issues.append("templateProfileOverride.voiceInvalid") }
        return issues
    }
    /// A validated candidate, including identical bytes, for the explicit apply/save path.
    public func prepared(_ form: Form, to draft: TemplateAuthoringDraft) -> TemplateAuthoringDraft? {
        guard canEdit, isCurrent(draft), issueKeys(form).isEmpty, let index,
              var rows = draft.advanced.value["profile"]?.object?["questions"]?.array,
              rows.indices.contains(index), var question = rows[index].object, question["key"]?.string == questionKey else { return nil }
        if form.enabled {
            guard let value = Self.number(form.threshold) else { return nil }
            var override: [String: TemplateAuthoringJSON] = [
                "requires": .array([.object(["op": .string("GTE"), "var": .string(Self.trim(form.variable)), "value": .number(value)])]),
                "option": .string(Self.trim(form.option))
            ]
            let voice = Self.trim(form.voice); if !voice.isEmpty { override["voice"] = .string(voice) }
            question["override"] = .object(override)
        } else if question["override"]?.object != nil {
            question.removeValue(forKey: "override")
        }
        rows[index] = .object(question)
        var next = draft; next.advanced.set("profile", "questions", .array(rows)); return next
    }
    public func applying(_ form: Form, to draft: TemplateAuthoringDraft) -> TemplateAuthoringDraft? {
        guard let next = prepared(form, to: draft), Self.snapshot(next) != source else { return nil }; return next
    }
    public static func snapshot(_ draft: TemplateAuthoringDraft) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return try? encoder.encode(draft)
    }
    private static func trim(_ text: String) -> String { TemplateAuthoringStory.sourceTrim(text) }
    private static func number(_ text: String) -> Double? {
        let text = trim(text)
        let value: Double? = text.isEmpty ? 0 : Double(text)
        guard let value, value.isFinite else { return nil }; return value
    }
    private static func readForm(_ raw: TemplateAuthoringJSON?, firstOption: String) -> (form: Form, supported: Bool) {
        let empty = Form(option: firstOption)
        guard let raw, raw != .null else { return (empty, true) }
        guard let override = raw.object, Set(override.keys).isSubset(of: ["requires", "option", "voice"]),
              let requires = override["requires"]?.array, requires.count == 1, let when = requires[0].object,
              Set(when.keys) == ["op", "var", "value"], when["op"]?.string == "GTE",
              let variable = when["var"]?.string,
              override["option"] == nil || override["option"]?.string != nil,
              override["voice"] == nil || override["voice"]?.string != nil else { return (empty, false) }
        let threshold: String
        if let text = when["value"]?.string { threshold = text }
        else if case .number(let value)? = when["value"], value.isFinite { threshold = value.rounded() == value ? String(format: "%.0f", value) : String(value) }
        else { return (empty, false) }
        return (.init(enabled: true, variable: variable, threshold: threshold, option: override["option"]?.string ?? "", voice: override["voice"]?.string ?? ""), true)
    }
}
