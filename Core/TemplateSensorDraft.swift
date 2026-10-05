import Foundation

/// Local configuration only. Original source remains exact; unfinished input is
/// separate and always takes precedence in preview. No device or network API.
public struct TemplateSensorDraft: Codable, Equatable {
    public enum Kind: String, Codable, CaseIterable, Identifiable {
        case still, steps, audioClip = "audio_clip"
        public var id: String { rawValue }
        public var labelKey: String { "sensorDraft.kind." + rawValue }
        public var parameters: [Parameter] {
            switch self { case .still: return [.durationSec]; case .steps: return [.targetSteps, .windowSec]; case .audioClip: return [.minDurationSec] }
        }
    }
    public enum Parameter: String, CaseIterable {
        case durationSec, targetSteps, windowSec, minDurationSec
        public var maximum: Int {
            switch self { case .durationSec: return 600; case .targetSteps: return 100_000; case .windowSec: return 86_400; case .minDurationSec: return 60 }
        }
        public var labelKey: String { "sensorDraft.field." + rawValue }
    }
    public struct Working: Codable, Equatable {
        public var type: String?
        public var inputs: [String: String]
        public init(type: String?, inputs: [String: String] = [:]) { self.type = type; self.inputs = inputs }
    }
    public let originalType: String?
    public let originalConfig: String?
    public private(set) var working: Working?
    public init(type: String? = nil, config: String? = nil) {
        originalType = type; originalConfig = config; working = nil
    }
    public var selectedType: String? {
        if let working { return working.type }
        return originalType
    }
    public var kind: Kind? { selectedType.flatMap(Kind.init(rawValue:)) }
    private var sourceProjection: OwnedTemplateSensorConfiguration {
        .init(type: originalType.map(OwnedTemplateText.value) ?? .missing,
              config: originalConfig.map(OwnedTemplateText.value) ?? .missing)
    }
    private var knownSourceInputs: [String: Int]? {
        guard let kind = originalType.flatMap(Kind.init(rawValue:)), let raw = originalConfig,
              raw.utf16.count <= 2_000,
              let fields = try? JSONDecoder().decode([String: Int].self, from: Data(raw.utf8)) else { return nil }
        let projection = sourceProjection
        for key in fields.keys {
            guard let parameter = Parameter(rawValue: key), kind.parameters.contains(parameter),
                  let ownerParameter = OwnedTemplateSensorConfiguration.Parameter(rawValue: key),
                  case .value = projection.value(ownerParameter) else { return nil }
        }
        return fields
    }
    /// Unsupported or ambiguous historical data can be saved, but never rewritten.
    public var canEdit: Bool {
        let sourceIsNew = originalType == nil && originalConfig == nil
        let sourceIsKnownMissing = originalType.flatMap(Kind.init(rawValue:)) != nil && originalConfig == nil
        let sourceIsKnownValid = knownSourceInputs != nil
        guard sourceIsNew || sourceIsKnownMissing || sourceIsKnownValid else { return false }
        guard let working else { return true }
        return (working.type == nil || working.type.flatMap(Kind.init(rawValue:)) != nil)
            && working.inputs.keys.allSatisfy { Parameter(rawValue: $0) != nil }
    }
    public func input(_ parameter: Parameter) -> String {
        if let working { return working.inputs[parameter.rawValue] ?? "" }
        guard let value = knownSourceInputs?[parameter.rawValue] else { return "" }
        return String(value)
    }
    private mutating func beginEditing() {
        guard working == nil else { return }
        var inputs: [String: String] = [:]
        for parameter in kind?.parameters ?? [] { inputs[parameter.rawValue] = input(parameter) }
        working = Working(type: originalType, inputs: inputs)
    }
    public mutating func select(_ kind: Kind) {
        guard canEdit, self.kind != kind else { return }
        beginEditing(); working?.type = kind.rawValue
    }
    public mutating func set(_ parameter: Parameter, text: String) {
        guard canEdit, kind?.parameters.contains(parameter) == true, input(parameter) != text else { return }
        beginEditing(); working?.inputs[parameter.rawValue] = text
    }
    public func integer(_ parameter: Parameter) -> Int? {
        let text = input(parameter)
        guard text.range(of: #"\A[0-9]+\z"#, options: .regularExpression) != nil,
              let value = Int(text), (1...parameter.maximum).contains(value) else { return nil }
        return value
    }
    public var isValid: Bool {
        guard canEdit, let kind else { return false }
        return kind.parameters.allSatisfy { integer($0) != nil }
    }
    /// Side-effect-free configuration preview, never an outbound template payload.
    public func configurationJSON() throws -> String {
        guard isValid, let kind else { throw TemplateAuthoringError.invalidDraft }
        if working == nil, let originalConfig { return originalConfig }
        var fields: [String: Int] = [:]
        for parameter in kind.parameters {
            guard let value = integer(parameter) else { throw TemplateAuthoringError.invalidDraft }
            fields[parameter.rawValue] = value
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let raw = String(decoding: try encoder.encode(fields), as: UTF8.self)
        guard raw.utf16.count <= 2_000 else { throw TemplateAuthoringError.invalidDraft }
        return raw
    }
}
