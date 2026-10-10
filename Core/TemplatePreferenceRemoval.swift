import Foundation

/// An explicit, local-only deletion projection. Surviving JSON is never re-encoded.
/// This is structural editing, not questionnaire validation or publication approval.
public struct TemplatePreferenceRemoval {
    public enum Failure: Error, Equatable { case unsupported, limit, minimum, stale }
    public enum Target: Equatable {
        case question(Int)
        case option(question: Int, index: Int)
    }
    public struct Option: Identifiable {
        public let id: Int
        public let text: String
    }
    public struct Question: Identifiable {
        public let id: Int
        public let title: String
        public let options: [Option]
        public var canRemoveOption: Bool { options.count > 2 }
    }
    public let source: String
    public let questions: [Question]
    public var canRemoveQuestion: Bool { questions.count > 1 }
    private let steps: [PreferenceRemovalNode]

    public init(source: String) throws {
        var parser = PreferenceRemovalParser(source: source)
        let root = try parser.parse()
        guard let steps = root.member("steps")?.rows, (1...128).contains(steps.count) else { throw Failure.unsupported }
        var questions: [Question] = [], optionCount = 0
        for (index, step) in steps.enumerated() {
            guard let title = step.member("title")?.text, let options = step.member("options")?.rows,
                  (2...64).contains(options.count) else { throw Failure.unsupported }
            optionCount += options.count
            guard optionCount <= 512 else { throw Failure.limit }
            let projected = try options.enumerated().map { position, value -> Option in
                guard let text = value.member("text")?.text else { throw Failure.unsupported }
                return Option(id: position, text: text)
            }
            questions.append(.init(id: index, title: title, options: projected))
        }
        self.source = source; self.steps = steps; self.questions = questions
    }

    /// Bind indexes to the exact reviewed bytes, not normalized String equality.
    public func removing(_ target: Target, from currentSource: String) throws -> String {
        guard source.utf8.elementsEqual(currentSource.utf8) else { throw Failure.stale }
        let rows: [PreferenceRemovalNode], index: Int, minimum: Int
        switch target {
        case .question(let selected): rows = steps; index = selected; minimum = 1
        case .option(let question, let selected):
            guard steps.indices.contains(question), let options = steps[question].member("options")?.rows else { throw Failure.stale }
            rows = options; index = selected; minimum = 2
        }
        guard rows.indices.contains(index) else { throw Failure.stale }
        guard rows.count > minimum else { throw Failure.minimum }
        // Remove one value and one adjacent separator. Every surviving token, including
        // result bodies, unknown fields, large integers and escape spelling, stays exact.
        let range: Range<Int>
        if index + 1 < rows.count { range = rows[index].range.lowerBound..<rows[index + 1].range.lowerBound }
        else { range = rows[index - 1].range.upperBound..<rows[index].range.upperBound }
        var bytes = Array(source.utf8); bytes.removeSubrange(range)
        let result = String(decoding: bytes, as: UTF8.self)
        _ = try Self(source: result)
        return result
    }
}

private struct PreferenceRemovalNode {
    indirect enum Value {
        case object([Data: PreferenceRemovalNode]), array([PreferenceRemovalNode]), text(String), scalar
    }
    let range: Range<Int>
    let value: Value
    func member(_ key: String) -> Self? {
        guard case .object(let members) = value else { return nil }; return members[Data(key.utf8)]
    }
    var rows: [Self]? { if case .array(let rows) = value { return rows }; return nil }
    var text: String? { if case .text(let text) = value { return text }; return nil }
}

/// Bounded lexical JSON parsing retains token ranges and exact decoded key bytes.
/// Duplicate keys are rejected instead of silently selecting one occurrence.
private struct PreferenceRemovalParser {
    let source: String
    private var bytes: [UInt8] = []
    private var offset = 0
    private var nodeCount = 0
    init(source: String) { self.source = source }
    mutating func parse() throws -> PreferenceRemovalNode {
        guard source.utf8.count <= 1_048_576 else { throw TemplatePreferenceRemoval.Failure.limit }
        bytes = Array(source.utf8)
        let root = try read(depth: 0); space()
        guard offset == bytes.count else { throw TemplatePreferenceRemoval.Failure.unsupported }
        return root
    }
    private mutating func space() {
        while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 }
    }
    private mutating func take(_ byte: UInt8) -> Bool {
        space(); guard offset < bytes.count, bytes[offset] == byte else { return false }; offset += 1; return true
    }
    private mutating func read(depth: Int) throws -> PreferenceRemovalNode {
        nodeCount += 1
        guard depth <= 64, nodeCount <= 20_000, !Task.isCancelled else { throw TemplatePreferenceRemoval.Failure.limit }
        space(); let start = offset
        guard offset < bytes.count else { throw TemplatePreferenceRemoval.Failure.unsupported }
        let value: PreferenceRemovalNode.Value
        switch bytes[offset] {
        case 123:
            offset += 1; var members: [Data: PreferenceRemovalNode] = [:]
            if !take(125) {
                while true {
                    space(); let key = Data(try quoted().utf8)
                    guard members[key] == nil, take(58) else { throw TemplatePreferenceRemoval.Failure.unsupported }
                    members[key] = try read(depth: depth + 1)
                    if take(125) { break }
                    guard take(44) else { throw TemplatePreferenceRemoval.Failure.unsupported }
                }
            }
            value = .object(members)
        case 91:
            offset += 1; var rows: [PreferenceRemovalNode] = []
            if !take(93) {
                while true {
                    rows.append(try read(depth: depth + 1))
                    if take(93) { break }
                    guard take(44) else { throw TemplatePreferenceRemoval.Failure.unsupported }
                }
            }
            value = .array(rows)
        case 34: value = .text(try quoted())
        case 116: try literal("true"); value = .scalar
        case 102: try literal("false"); value = .scalar
        case 110: try literal("null"); value = .scalar
        default:
            while offset < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[offset]) { offset += 1 }
            let token = String(decoding: bytes[start..<offset], as: UTF8.self)
            guard token.range(of: "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$", options: .regularExpression) != nil else {
                throw TemplatePreferenceRemoval.Failure.unsupported
            }
            value = .scalar
        }
        return .init(range: start..<offset, value: value)
    }
    private mutating func quoted() throws -> String {
        guard offset < bytes.count, bytes[offset] == 34 else { throw TemplatePreferenceRemoval.Failure.unsupported }
        let start = offset; offset += 1; var escaped = false
        while offset < bytes.count {
            let byte = bytes[offset]; offset += 1
            if escaped { escaped = false }
            else if byte == 92 { escaped = true }
            else if byte == 34 {
                guard let value = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<offset])) else {
                    throw TemplatePreferenceRemoval.Failure.unsupported
                }
                return value
            }
        }
        throw TemplatePreferenceRemoval.Failure.unsupported
    }
    private mutating func literal(_ token: String) throws {
        let expected = Array(token.utf8)
        guard offset + expected.count <= bytes.count,
              bytes[offset..<(offset + expected.count)].elementsEqual(expected) else { throw TemplatePreferenceRemoval.Failure.unsupported }
        offset += expected.count
    }
}
