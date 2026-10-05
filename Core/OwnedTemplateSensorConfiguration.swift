import Foundation

/// Read-only owner projection. No provider, editor defaults, serialization or action API.
public struct OwnedTemplateSensorConfiguration {
    public enum Kind: String { case still, steps, audioClip = "audio_clip" }
    public enum Status: Equatable { case missing, null, invalid, unsupportedType, ready, partial }
    public enum Value: Equatable { case missing, null, invalid, value(Int) }
    public enum Parameter: String, CaseIterable {
        case durationSec, targetSteps, windowSec, minDurationSec
        var maximum: Int {
            switch self {
            case .durationSec: return 600
            case .targetSteps: return 100_000
            case .windowSec: return 86_400
            case .minDurationSec: return 60
            }
        }
    }
    public let kind: Kind?
    public let status: Status
    public let parameters: [Parameter]
    private let values: [Parameter: Value]
    public func value(_ parameter: Parameter) -> Value { values[parameter] ?? .missing }

    init(type: OwnedTemplateText, config: OwnedTemplateText) {
        kind = type.value.flatMap(Kind.init(rawValue:))
        switch kind {
        case .still: parameters = [.durationSec]
        case .steps: parameters = [.targetSteps, .windowSec]
        case .audioClip: parameters = [.minDurationSec]
        case nil: parameters = []
        }
        guard kind != nil else { status = .unsupportedType; values = [:]; return }
        switch config {
        case .missing: status = .missing; values = [:]
        case .null: status = .null; values = [:]
        case .unsupported: status = .invalid; values = [:]
        case .value(let raw):
            // Match backend Java String length; never coerce strings, doubles or booleans.
            guard raw.utf16.count <= 2_000, Self.hasBoundedJSONDepth(raw),
                  let wire = try? JSONDecoder().decode(PlayWireValue.self, from: Data(raw.utf8)),
                  let fields = wire.object else { status = .invalid; values = [:]; return }
            let literals = Self.topLevelLiterals(raw)
            var parsed: [Parameter: Value] = [:]
            for parameter in parameters {
                guard let field = fields[parameter.rawValue] else { parsed[parameter] = .missing; continue }
                if literals[parameter.rawValue] == "unsupported-duplicate" { parsed[parameter] = .invalid }
                else if case .null = field { parsed[parameter] = .null }
                else if let literal = literals[parameter.rawValue], Self.isCanonicalIntegerToken(literal),
                        let number = field.integer, number > 0, number <= parameter.maximum { parsed[parameter] = .value(number) }
                else { parsed[parameter] = .invalid }
            }
            values = parsed
            let allValid = parsed.values.allSatisfy { if case .value = $0 { return true }; return false }
            // Capture only a local immutable copy while status is not initialized yet.
            let configuredParameters = parameters
            let unknown = fields.keys.contains { key in !configuredParameters.contains { $0.rawValue == key } }
            status = !allValid ? .invalid : (unknown ? .partial : .ready)
        }
    }

    static func isCanonicalIntegerToken(_ token: String) -> Bool {
        token.range(of: #"\A[0-9]+\z"#, options: .regularExpression) != nil
    }

    /// Conservative inspection boundary, checked iteratively before recursive decoding.
    /// Brackets inside escaped JSON strings do not count. Original bytes stay untouched.
    private static func hasBoundedJSONDepth(_ raw: String) -> Bool {
        var depth = 0, quoted = false, escaped = false
        for char in raw {
            if quoted {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { quoted = false }
            } else if char == "\"" { quoted = true }
            else if char == "{" || char == "[" {
                depth += 1
                if depth > 16 { return false }
            } else if char == "}" || char == "]" {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return depth == 0 && !quoted
    }

    /// JSONDecoder can accept 1.0 as Int. Preserve backend integer-token semantics by
    /// checking the original top-level value spelling after the full JSON parse succeeds.
    /// Unknown nested content never enters the display projection.
    private static func topLevelLiterals(_ raw: String) -> [String: String] {
        var depth = 0, quoted = false, escaped = false, pair = ""
        var pairs: [String] = []
        for char in raw {
            if quoted {
                if depth >= 1 { pair.append(char) }
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == "\"" { quoted = false }
                continue
            }
            if char == "\"" { quoted = true; pair.append(char); continue }
            if char == "{" || char == "[" { if depth >= 1 { pair.append(char) }; depth += 1 }
            else if char == "}" || char == "]" {
                depth -= 1
                if depth == 0 { pairs.append(pair); pair = "" } else { pair.append(char) }
            } else if char == "," && depth == 1 { pairs.append(pair); pair = "" }
            else if depth >= 1 { pair.append(char) }
        }
        var result: [String: String] = [:]
        for pair in pairs {
            var inString = false, escape = false
            for index in pair.indices {
                let char = pair[index]
                if inString {
                    if escape { escape = false }
                    else if char == "\\" { escape = true }
                    else if char == "\"" { inString = false }
                } else if char == "\"" { inString = true }
                else if char == ":" {
                    let keyRaw = String(pair[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let key = try? JSONDecoder().decode(String.self, from: Data(keyRaw.utf8)) {
                        let value = String(pair[pair.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        // Duplicate top-level fields are ambiguous; fail their display closed.
                        result[key] = result[key] == nil ? value : "unsupported-duplicate"
                    }
                    break
                }
            }
        }
        return result
    }
}
