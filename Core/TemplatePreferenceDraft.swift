import Foundation

/// A local-only view of current author text. The source string is never reserialized.
public struct TemplatePreferenceDraftCheck: Equatable, Sendable {
    public enum Status: String, Sendable { case valid, invalid, unsupported, incomplete }
    public struct Field: Equatable, Identifiable, Sendable {
        public let path: String
        public let value: String
        public var id: String { path }
    }
    public let status: Status
    public let path: String
    public let messageKey: String
    public let fields: [Field]
    public let unknownPaths: [String]
    public var canPreview: Bool { status == .valid }
    /// Explicit invocation only: callers must not run enumeration on every keystroke.
    public static func inspect(_ raw: String, workLimit: Int = 1_000_000) -> Self {
        do {
            var parser = PreferenceSourceParser(raw: raw)
            let root = try parser.parse()
            var validator = PreferenceSourceValidator(work: max(0, workLimit))
            try validator.validate(root)
            return .init(status: .valid, path: "$", messageKey: "templateAuthor.preference.valid", fields: validator.fields, unknownPaths: validator.unknown)
        } catch let failure as PreferenceSourceFailure {
            return .init(status: failure.status, path: failure.path, messageKey: "templateAuthor.preference.error." + failure.code, fields: [], unknownPaths: [])
        } catch {
            return .init(status: .invalid, path: "$", messageKey: "templateAuthor.preference.error.json", fields: [], unknownPaths: [])
        }
    }
    /// The editable example in the source mini editor; it is installed only by an explicit action.
    public static let example = #"""
    {
      "steps": [{"key":"space","type":"single","title":"你现在的空间更像哪一种?","options":[
        {"key":"A","text":"小而紧凑","scores":{"compact":2,"open":0}},
        {"key":"B","text":"开阔但杂乱","scores":{"compact":0,"open":2}}
      ]}],
      "dimensions":["compact","open"],
      "tiebreak":{"key":"tradeoff","type":"single","title":"如果只能先改一个?","options":[
        {"key":"A","text":"先减物品","scores":{"compact":1}},
        {"key":"B","text":"先改动线","scores":{"open":1}}
      ]},
      "results":{
        "compact":{"title":"小空间先减负","body":"因为你选择了{{choices}}","nextStep":"清掉一层柜子","nextStepDays":7},
        "open":{"title":"开放空间先定动线","body":"因为你选择了{{choices}}","nextStep":"重排一次动线","nextStepDays":30}
      },
      "tagConsumes":["space_constraints"],
      "tagOutput":{"code":"space_constraints","fromDimension":true,"recipientLabel":"本主题下一家生活方式店","purpose":"生成适合你空间条件的本站建议","revocable":true}
    }
    """#
}
private struct PreferenceSourceFailure: Error {
    let status: TemplatePreferenceDraftCheck.Status
    let path: String
    let code: String
    init(_ code: String, _ path: String = "$", _ status: TemplatePreferenceDraftCheck.Status = .invalid) {
        self.code = code; self.path = path; self.status = status
    }
}
/// Numbers retain their lexical kind: Jackson isInt rejects 7.0 and "7".
private indirect enum PreferenceSourceValue {
    case object([String: Self]), array([Self]), string(String), number(String), bool(Bool), null
    var object: [String: Self]? { if case .object(let value) = self { return value }; return nil }
    var array: [Self]? { if case .array(let value) = self { return value }; return nil }
    var string: String? { if case .string(let value) = self { return value }; return nil }
    var int: Int? {
        guard case .number(let raw) = self, !raw.contains("."), !raw.contains("e"), !raw.contains("E"),
              let value = Int(raw), value >= Int(Int32.min), value <= Int(Int32.max) else { return nil }
        return value
    }
    var isNull: Bool { if case .null = self { return true }; return false }
}
private struct PreferenceSourceParser {
    let raw: String
    private var bytes: [UInt8] = []
    private var offset = 0
    init(raw: String) { self.raw = raw }
    mutating func parse() throws -> PreferenceSourceValue {
        guard raw.utf8.count <= 1_048_576 else { throw PreferenceSourceFailure("budget", "$", .incomplete) }
        bytes = Array(raw.utf8)
        let value = try read(depth: 0)
        space(); guard offset == bytes.count else { throw PreferenceSourceFailure("type", "$", .unsupported) }
        return value
    }
    private mutating func space() { while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 } }
    private mutating func take(_ byte: UInt8) -> Bool {
        space(); guard offset < bytes.count, bytes[offset] == byte else { return false }; offset += 1; return true
    }
    private mutating func read(depth: Int) throws -> PreferenceSourceValue {
        guard !Task.isCancelled, depth <= 64 else { throw PreferenceSourceFailure("budget", "$", .incomplete) }
        space(); guard offset < bytes.count else { throw PreferenceSourceFailure("json") }
        switch bytes[offset] {
        case 123:
            offset += 1; var values: [String: PreferenceSourceValue] = [:]
            if take(125) { return .object(values) }
            repeat {
                space(); let key = try quoted()
                guard key.utf8.elementsEqual(key.precomposedStringWithCanonicalMapping.utf8) else { throw PreferenceSourceFailure("type", "$", .unsupported) }
                guard take(58) else { throw PreferenceSourceFailure("json") }
                values[key] = try read(depth: depth + 1)
                if take(125) { return .object(values) }
            } while take(44)
            throw PreferenceSourceFailure("json")
        case 91:
            offset += 1; var values: [PreferenceSourceValue] = []
            if take(93) { return .array(values) }
            repeat {
                values.append(try read(depth: depth + 1))
                if take(93) { return .array(values) }
            } while take(44)
            throw PreferenceSourceFailure("json")
        case 34: return .string(try quoted())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default:
            let start = offset
            while offset < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[offset]) { offset += 1 }
            let number = String(decoding: bytes[start..<offset], as: UTF8.self)
            guard number.range(of: "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$", options: .regularExpression) != nil else { throw PreferenceSourceFailure("json") }
            return .number(number)
        }
    }
    private mutating func quoted() throws -> String {
        guard offset < bytes.count, bytes[offset] == 34 else { throw PreferenceSourceFailure("json") }
        let start = offset; offset += 1; var escaped = false
        while offset < bytes.count {
            let value = bytes[offset]; offset += 1
            if escaped { escaped = false }
            else if value == 92 { escaped = true }
            else if value == 34 {
                guard let result = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<offset])) else { throw PreferenceSourceFailure("json") }
                return result
            }
        }
        throw PreferenceSourceFailure("json")
    }
    private mutating func literal(_ value: String) throws {
        let expected = Array(value.utf8)
        guard offset + expected.count <= bytes.count, Array(bytes[offset..<(offset + expected.count)]) == expected else { throw PreferenceSourceFailure("json") }
        offset += expected.count
    }
}
private struct PreferenceSourceValidator {
    struct Option { let scores: [String: Int]; let notApplicable: Bool }
    var work: Int
    var fields: [TemplatePreferenceDraftCheck.Field] = []
    var unknown: [String] = []
    init(work: Int) { self.work = work }
    private let tags: Set<String> = ["space_constraints", "social_mode", "arrival_window", "expression_mode"]
    private mutating func tick(_ count: Int = 1) throws {
        guard !Task.isCancelled, work >= count, fields.count <= 2_000 else { throw PreferenceSourceFailure("budget", "$", .incomplete) }; work -= count
    }
    private func object(_ value: PreferenceSourceValue?, _ path: String) throws -> [String: PreferenceSourceValue] {
        guard let result = value?.object else { throw PreferenceSourceFailure("object", path) }; return result
    }
    private func array(_ value: PreferenceSourceValue?, _ path: String, nonempty: Bool = true) throws -> [PreferenceSourceValue] {
        guard let result = value?.array, !nonempty || !result.isEmpty else { throw PreferenceSourceFailure("array", path) }; return result
    }
    private mutating func text(_ value: PreferenceSourceValue?, _ path: String) throws -> String {
        guard let value, !value.isNull else { throw PreferenceSourceFailure("required", path) }
        guard let result = value.string else { throw PreferenceSourceFailure("type", path, .unsupported) }
        guard result.unicodeScalars.contains(where: { $0.value > 32 }) else { throw PreferenceSourceFailure("required", path) }
        fields.append(.init(path: path, value: result)); return result
    }
    private mutating func identity(_ value: PreferenceSourceValue?, _ path: String) throws -> String {
        let result = try text(value, path)
        // Java identifiers compare exact code units; Swift String equality normalizes canonically.
        // Never silently merge distinct authored identifiers or rewrite their source text.
        guard result.utf8.elementsEqual(result.precomposedStringWithCanonicalMapping.utf8) else { throw PreferenceSourceFailure("type", path, .unsupported) }
        return result
    }
    private mutating func boolean(_ value: PreferenceSourceValue?, _ path: String, requiredTrue: Bool = false) throws -> Bool {
        let result: Bool
        if value == nil || value?.isNull == true { result = false }
        else if case .bool(let bool) = value! { result = bool }
        else { throw PreferenceSourceFailure("type", path, .unsupported) }
        if requiredTrue && !result { throw PreferenceSourceFailure("true", path) }
        if value != nil { fields.append(.init(path: path, value: result ? "true" : "false")) }
        return result
    }
    private mutating func extensions(_ object: [String: PreferenceSourceValue], _ known: Set<String>, _ path: String) {
        unknown += object.keys.filter { !known.contains($0) }.sorted().map { path + "." + $0 }
    }
    mutating func validate(_ root: PreferenceSourceValue) throws {
        let config = try object(root, "$")
        extensions(config, ["steps", "dimensions", "tiebreak", "results", "notApplicableResult", "tagConsumes", "tagOutput"], "$")
        let rawDimensions = try array(config["dimensions"], "$.dimensions")
        var dimensions: [String] = [], seenDimensions = Set<String>()
        for (index, value) in rawDimensions.enumerated() {
            try tick(); let name = try identity(value, "$.dimensions[\(index)]")
            guard seenDimensions.insert(name).inserted else { throw PreferenceSourceFailure("duplicate", "$.dimensions[\(index)]") }; dimensions.append(name)
        }
        let dimensionSet = Set(dimensions)
        var keys = Set<String>(), hasNA = false
        let rawSteps = try array(config["steps"], "$.steps")
        var steps: [[Option]] = []
        for (index, raw) in rawSteps.enumerated() {
            steps.append(try step(raw, "$.steps[\(index)]", dimensions: dimensionSet, keys: &keys, hasNA: &hasNA))
        }
        var tie: [Option]?
        if let raw = config["tiebreak"], !raw.isNull { tie = try step(raw, "$.tiebreak", dimensions: dimensionSet, keys: &keys, hasNA: &hasNA) }
        if dimensions.count > 1 && tie == nil { throw PreferenceSourceFailure("tiebreak", "$.tiebreak") }
        try reachable(steps, tie, dimensions)
        let results = try object(config["results"], "$.results")
        guard Set(results.keys) == dimensionSet else { throw PreferenceSourceFailure("results", "$.results") }
        var coupons: [Int64?] = []
        for dimension in dimensions { coupons.append(try result(results[dimension], "$.results." + dimension, evidence: true)) }
        if dimensions.count > 1, let coupon = coupons.first ?? nil, coupons.allSatisfy({ $0 == coupon }) { throw PreferenceSourceFailure("coupon", "$.results") }
        if hasNA { _ = try result(config["notApplicableResult"], "$.notApplicableResult", evidence: false) }
        else if let unused = config["notApplicableResult"], !unused.isNull {
            // Backend does not validate an unused NA branch. Preserve it without claiming semantics.
            unknown.append("$.notApplicableResult (unused)")
        }
        if let output = config["tagOutput"], !output.isNull {
            let value = try object(output, "$.tagOutput")
            extensions(value, ["code", "fromDimension", "recipientLabel", "purpose", "revocable"], "$.tagOutput")
            let code = try text(value["code"], "$.tagOutput.code")
            guard tags.contains(code) else { throw PreferenceSourceFailure("tag", "$.tagOutput.code") }
            _ = try boolean(value["fromDimension"], "$.tagOutput.fromDimension", requiredTrue: true)
            _ = try text(value["recipientLabel"], "$.tagOutput.recipientLabel")
            _ = try text(value["purpose"], "$.tagOutput.purpose")
            _ = try boolean(value["revocable"], "$.tagOutput.revocable", requiredTrue: true)
        }
        if let raw = config["tagConsumes"], !raw.isNull {
            for (index, value) in try array(raw, "$.tagConsumes", nonempty: false).enumerated() {
                try tick(); let path = "$.tagConsumes[\(index)]", code = try text(value, path)
                guard tags.contains(code) else { throw PreferenceSourceFailure("tag", path) }
            }
        }
        guard fields.count <= 2_000, unknown.count <= 2_000 else { throw PreferenceSourceFailure("budget", "$", .incomplete) }
    }
    private mutating func step(_ raw: PreferenceSourceValue, _ path: String, dimensions: Set<String>, keys: inout Set<String>, hasNA: inout Bool) throws -> [Option] {
        try tick(); let value = try object(raw, path)
        extensions(value, ["key", "type", "title", "options"], path)
        let key = try identity(value["key"], path + ".key")
        guard keys.insert(key).inserted else { throw PreferenceSourceFailure("duplicate", path + ".key") }
        let type = try text(value["type"], path + ".type")
        guard ["single", "discard"].contains(type) else { throw PreferenceSourceFailure("stepType", path + ".type") }
        _ = try text(value["title"], path + ".title")
        let rows = try array(value["options"], path + ".options")
        guard rows.count >= 2 else { throw PreferenceSourceFailure("options", path + ".options") }
        var optionKeys = Set<String>(), options: [Option] = []
        for (index, row) in rows.enumerated() {
            try tick(); let optionPath = path + ".options[\(index)]", option = try object(row, optionPath)
            extensions(option, ["key", "text", "scores", "notApplicable"], optionPath)
            let optionKey = try identity(option["key"], optionPath + ".key")
            guard optionKeys.insert(optionKey).inserted else { throw PreferenceSourceFailure("duplicate", optionPath + ".key") }
            _ = try text(option["text"], optionPath + ".text")
            let scores = try object(option["scores"], optionPath + ".scores")
            var parsed: [String: Int] = [:]
            for name in scores.keys.sorted() {
                try tick(); let scorePath = optionPath + ".scores." + name
                guard dimensions.contains(name), let score = scores[name]?.int, (0...2).contains(score) else { throw PreferenceSourceFailure("score", scorePath) }
                parsed[name] = score; fields.append(.init(path: scorePath, value: String(score)))
            }
            let na = try boolean(option["notApplicable"], optionPath + ".notApplicable")
            hasNA = hasNA || na; options.append(.init(scores: parsed, notApplicable: na))
        }
        return options
    }
    private mutating func result(_ raw: PreferenceSourceValue?, _ path: String, evidence: Bool) throws -> Int64? {
        try tick(); let value = try object(raw, path)
        extensions(value, ["title", "body", "nextStep", "nextStepDays", "couponId"], path)
        _ = try text(value["title"], path + ".title")
        let body = try text(value["body"], path + ".body")
        if evidence && !body.contains("{{choices}}") { throw PreferenceSourceFailure("evidence", path + ".body") }
        _ = try text(value["nextStep"], path + ".nextStep")
        guard let days = value["nextStepDays"]?.int, [7, 30].contains(days) else { throw PreferenceSourceFailure("days", path + ".nextStepDays") }
        fields.append(.init(path: path + ".nextStepDays", value: String(days)))
        guard let coupon = value["couponId"], !coupon.isNull else { return nil }
        // Jackson canConvertToLong allows fractional numeric coupons; native does not interpret these.
        if case .number(let raw) = coupon, let integer = Int64(raw) {
            fields.append(.init(path: path + ".couponId", value: raw)); return integer
        }
        throw PreferenceSourceFailure("type", path + ".couponId", .unsupported)
    }
    private mutating func reachable(_ steps: [[Option]], _ tie: [Option]?, _ dimensions: [String]) throws {
        var states = [Dictionary(uniqueKeysWithValues: dimensions.map { ($0, 0) })]
        for (index, step) in steps.enumerated() {
            var next: [[String: Int]] = []
            for state in states {
                for option in step where !option.notApplicable {
                    try tick(dimensions.count + option.scores.count + 1)
                    var score = state; for (key, value) in option.scores { score[key, default: 0] += value }
                    next.append(score)
                    guard next.count <= 4096 else { throw PreferenceSourceFailure("combinations", "$.steps[\(index)]") }
                }
            }
            states = next
        }
        var reachable = Set<String>()
        for state in states {
            try tick(dimensions.count + 1); let maximum = state.values.max()
            let winners = state.filter { $0.value == maximum }.map(\.key)
            if winners.count == 1 { reachable.insert(winners[0]); continue }
            guard let tie else { continue }
            for option in tie where !option.notApplicable {
                try tick(dimensions.count * 2 + option.scores.count + 1)
                var score = state; for (key, value) in option.scores { score[key, default: 0] += value }
                let best = score.values.max(), resolved = score.filter { $0.value == best }.map(\.key)
                guard resolved.count == 1 else { throw PreferenceSourceFailure("tie", "$.tiebreak") }; reachable.insert(resolved[0])
            }
        }
        guard reachable == Set(dimensions) else { throw PreferenceSourceFailure("reachable", "$.dimensions") }
    }
}
