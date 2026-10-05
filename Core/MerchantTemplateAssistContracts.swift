import Foundation

public enum MerchantTemplateAssistFailure: String, Error, Equatable {
    case shopNameRequired, promptRequired, permission, provider, malformed, empty, disabled, unknown, cancelled, stale
    public var messageKey: String { "merchant.assist.error." + rawValue }
    public var retryable: Bool { [.provider, .malformed, .empty, .shopNameRequired, .promptRequired].contains(self) }
    public static func rejection(_ message: String) -> Self {
        if message.contains("当前身份暂不支持") || message.contains("请先登录") { return .permission }
        return .provider
    }
}
public struct MerchantTemplateAssistInput: Equatable {
    public let shopName: String
    public let prompt: String
    public let method: MerchantTemplateMethod?
    public init(shopName: String, prompt: String, method: MerchantTemplateMethod?) throws {
        self.shopName = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines); self.method = method
        guard !self.shopName.isEmpty else { throw MerchantTemplateAssistFailure.shopNameRequired }
        guard !self.prompt.isEmpty else { throw MerchantTemplateAssistFailure.promptRequired }
    }
    public var assistance: PublishingAssistance {
        .template(shopName: shopName, extraNote: prompt, category: "", reward: "", playStyle: "", validationMethod: method?.rawValue)
    }
}
/// AI's optionA...D names are deliberately distinct from the save API's questionA...D.
public enum MerchantTemplateAssistField: String, CaseIterable, Hashable {
    case title, description, questionName, questionAnswer, optionA, optionB, optionC, optionD, feedbackText, correctAnswer, validationMethod
    public var titleKey: String { "merchant.assist.field." + rawValue }
    var keyPath: WritableKeyPath<MerchantNodeTemplate, String>? {
        switch self {
        case .title: return \.title
        case .description: return \.description
        case .questionName: return \.questionName
        case .questionAnswer: return \.questionAnswer
        case .optionA: return \.optionA
        case .optionB: return \.optionB
        case .optionC: return \.optionC
        case .optionD: return \.optionD
        case .feedbackText: return \.feedbackText
        case .correctAnswer: return \.correctAnswer
        case .validationMethod: return nil
        }
    }
    func value(in draft: MerchantNodeTemplate) -> String {
        if let keyPath { return draft[keyPath: keyPath] }
        return draft.method.map { String($0.rawValue) } ?? ""
    }
}
/// Field revisions preserve an intentional edit followed by a clear, even when the text
/// ends up equal to its original value. Loading/discarding creates a separate draft identity.
public struct MerchantTemplateAssistEdits: Equatable {
    private var versions: [MerchantTemplateAssistField: UInt64] = [:]
    public init() {}
    public mutating func record(from old: MerchantNodeTemplate, to new: MerchantNodeTemplate) {
        for field in MerchantTemplateAssistField.allCases where field.value(in: old) != field.value(in: new) {
            versions[field, default: 0] += 1
        }
    }
    public func unchanged(_ field: MerchantTemplateAssistField, since captured: Self) -> Bool { versions[field, default: 0] == captured.versions[field, default: 0] }
}
public struct MerchantTemplateAssistResult: Equatable {
    public let raw: [String: ProjectEditJSON]
    public init(_ response: ProjectEditJSON) throws {
        guard let object = response.object else { throw MerchantTemplateAssistFailure.malformed }
        if let error = object["parseError"], error != .null { throw MerchantTemplateAssistFailure.malformed }
        // Match source: template first, node second, then the root object.
        let inner = object["template"].flatMap { $0 == .null ? nil : $0 } ?? object["node"]
        raw = inner?.object ?? object
        if let error = raw["parseError"], error != .null { throw MerchantTemplateAssistFailure.malformed }
        for field in MerchantTemplateAssistField.allCases where field != .validationMethod {
            if let value = raw[field.rawValue], value != .null, value.text == nil { throw MerchantTemplateAssistFailure.malformed }
        }
    }
    public func text(_ key: String) -> String? {
        guard let value = raw[key]?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    /// Retain the source's six-field emptiness rule, including question-only responses.
    public var isEmpty: Bool { ["storyText", "ruleInstructions", "questionName", "questionAnswer", "hint1", "hint2"].allSatisfy { text($0) == nil } }
    public var method: MerchantTemplateMethod? {
        (raw["validationMethod"]?.integer ?? text("validationMethod").flatMap(Int.init)).flatMap(MerchantTemplateMethod.init(rawValue:))
    }
    public func suggestion(_ field: MerchantTemplateAssistField) -> String? {
        if field == .description { return text("description") ?? text("storyText").map { String($0.prefix(30)) } }
        if field == .validationMethod { return method.map { String($0.rawValue) } }
        return text(field.rawValue)
    }
    /// Preserve every returned field for inspection, including future server fields. Story
    /// remains listed here: only its short fallback summary fits the existing description.
    public var unsupportedKeys: [String] {
        raw.keys.filter { key in
            guard let value = raw[key], value != .null else { return false }
            if let string = value.text, string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if key == "validationMethod" { return method == nil }
            return MerchantTemplateAssistField(rawValue: key) == nil
        }.sorted()
    }
    public func display(_ key: String) -> String {
        if let text = raw[key]?.text { return text }
        guard let value = raw[key], let data = try? JSONEncoder().encode(value) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    public func merge(into latest: MerchantNodeTemplate, captured: MerchantNodeTemplate,
                      edits: MerchantTemplateAssistEdits, capturedEdits: MerchantTemplateAssistEdits) -> MerchantNodeTemplate {
        guard !isEmpty, latest.id == captured.id else { return latest }
        var merged = latest
        func eligible(_ field: MerchantTemplateAssistField) -> Bool {
            field.value(in: captured).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            field.value(in: latest).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && edits.unchanged(field, since: capturedEdits)
        }
        for field in MerchantTemplateAssistField.allCases where field != .correctAnswer && field != .validationMethod {
            guard eligible(field), let keyPath = field.keyPath, let value = suggestion(field) else { continue }
            merged[keyPath: keyPath] = value
        }
        if eligible(.validationMethod), let method { merged.method = method }
        if merged.method == .quiz, eligible(.correctAnswer), let answer = text("correctAnswer")?.uppercased(),
           let index = ["A", "B", "C", "D"].firstIndex(of: answer) {
            let options = [merged.optionA, merged.optionB, merged.optionC, merged.optionD].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            // Do not assign AI's answer to a different, manually edited option.
            if merged.questionName.trimmingCharacters(in: .whitespacesAndNewlines) == text("questionName"),
               options.filter({ !$0.isEmpty }).count >= 2, !options[index].isEmpty, options[index] == text("option" + answer) {
                merged.correctAnswer = answer
            }
        }
        return merged
    }
}
