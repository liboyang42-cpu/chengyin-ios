import Foundation

/// Lossless JSON equality for server canonicalization readbacks. Does not depend on
/// floating-point rounding, key ordering, whitespace, or Foundation number/bool bridging.
indirect enum ContentDraftJSON: Equatable {
    case object([Data: ContentDraftJSON]), array([ContentDraftJSON]), string(Data)
    case number(negative: Bool, digits: String, exponent: Int), bool(Bool), null
    static func parse(_ text: String) throws -> Self {
        var parser = Parser(bytes: Array(text.utf8))
        let result = try parser.value(depth: 0)
        parser.space()
        guard parser.index == parser.bytes.count else { throw ContentDraftIssue.malformed }
        return result
    }
    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var peek: UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func space() { while let c = peek, [9, 10, 13, 32].contains(c) { index += 1 } }
        mutating func take(_ c: UInt8) -> Bool {
            guard peek == c else { return false }; index += 1; return true
        }
        mutating func require(_ c: UInt8) throws { guard take(c) else { throw ContentDraftIssue.malformed } }
        mutating func string() throws -> Data {
            let start = index; try require(34)
            while let c = peek {
                index += 1
                if c == 34 {
                    do { return Data(try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])).utf8) }
                    catch { throw ContentDraftIssue.malformed }
                }
                if c == 92 {
                    guard peek != nil else { throw ContentDraftIssue.malformed }
                    index += 1
                }
            }
            throw ContentDraftIssue.malformed
        }
        mutating func literal(_ text: String, result: ContentDraftJSON) throws -> ContentDraftJSON {
            let literal = Array(text.utf8)
            guard index + literal.count <= bytes.count, Array(bytes[index..<(index + literal.count)]) == literal else {
                throw ContentDraftIssue.malformed
            }
            index += literal.count; return result
        }
        func digit(_ c: UInt8?) -> Bool { c.map { (48...57).contains($0) } ?? false }
        mutating func number() throws -> ContentDraftJSON {
            let negative = take(45), start = index
            if take(48) { guard !digit(peek) else { throw ContentDraftIssue.malformed } }
            else {
                guard let c = peek, (49...57).contains(c) else { throw ContentDraftIssue.malformed }
                while digit(peek) { index += 1 }
            }
            var fraction = 0
            if take(46) {
                let fractionStart = index
                while digit(peek) { index += 1 }
                fraction = index - fractionStart
                guard fraction > 0 else { throw ContentDraftIssue.malformed }
            }
            let coefficientEnd = index
            var exponent = 0
            if take(101) || take(69) {
                let minus = take(45)
                if !minus { _ = take(43) }
                let exponentStart = index
                while digit(peek) {
                    // A bounded parser rejects pathological exponents rather than overflowing.
                    guard exponent <= 100_000 else { throw ContentDraftIssue.malformed }
                    exponent = exponent * 10 + Int(bytes[index] - 48); index += 1
                }
                guard index > exponentStart else { throw ContentDraftIssue.malformed }
                if minus { exponent = -exponent }
            }
            var coefficient = bytes[start..<coefficientEnd].filter { $0 != 46 }
            coefficient = Array(coefficient.drop(while: { $0 == 48 }))
            guard !coefficient.isEmpty else { return .number(negative: false, digits: "0", exponent: 0) }
            exponent -= fraction
            while coefficient.last == 48 { coefficient.removeLast(); exponent += 1 }
            return .number(negative: negative, digits: String(decoding: coefficient, as: UTF8.self), exponent: exponent)
        }
        mutating func value(depth: Int) throws -> ContentDraftJSON {
            guard depth <= 128 else { throw ContentDraftIssue.malformed }
            space()
            switch peek {
            case 34: return .string(try string())
            case 123:
                index += 1; space(); var result: [Data: ContentDraftJSON] = [:]
                if take(125) { return .object(result) }
                while true {
                    space(); let key = try string(); space(); try require(58)
                    guard result[key] == nil else { throw ContentDraftIssue.malformed }
                    result[key] = try value(depth: depth + 1); space()
                    if take(125) { return .object(result) }; try require(44)
                }
            case 91:
                index += 1; space(); var result: [ContentDraftJSON] = []
                if take(93) { return .array(result) }
                while true {
                    result.append(try value(depth: depth + 1)); space()
                    if take(93) { return .array(result) }; try require(44)
                }
            case 116: return try literal("true", result: .bool(true))
            case 102: return try literal("false", result: .bool(false))
            case 110: return try literal("null", result: .null)
            default: return try number()
            }
        }
    }
}
