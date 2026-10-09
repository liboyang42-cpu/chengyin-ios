import Foundation

/// Staged author declarations for the existing journeyRules field. This is not a
/// registered-key editor and never deletes keys, references or saved run state.
public struct ProjectInitialAttributes {
    public struct Row: Identifiable {
        public let id: UUID
        public var key: String
        public var label: String
        public var initial: String
        public var minimum: String
        public var maximum: String
        public var visible: Bool
        public let existingKey: String?
        fileprivate let source: [String: ProjectEditJSON]?
        public var isFlag: Bool { key.hasPrefix("clue.") || key.hasPrefix("tag.") }
    }
    public private(set) var rows: [Row] = []
    public private(set) var stateEnabled = false
    public private(set) var readOnly = false
    private let raw: ProjectEditJSON?
    private var root: [String: ProjectEditJSON] = [:]
    private var originalRows: [Row] = []
    private var originalEnabled = false

    public init(raw: ProjectEditJSON?) {
        self.raw = raw
        do {
            if let raw, raw != .null {
                guard let text = raw.text, text.utf8.count <= 16 * 1024 else { throw ProjectEditError.invalidDraft }
                if !Self.javaTrim(text).isEmpty {
                    root = try ApprovedTopicReleaseWire.envelope(Data(text.utf8))
                    try Self.validateIntegerTokens(text)
                    // Swift Dictionary equality merges canonically equivalent keys.
                    // Reject any imported object that cannot survive our exact-key
                    // wire representation instead of dropping an unknown field.
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                    let roundTrip = String(decoding: try encoder.encode(ProjectEditJSON.object(root)), as: UTF8.self)
                    guard try ContentDraftJSON.parse(text) == ContentDraftJSON.parse(roundTrip) else { throw ProjectEditError.invalidDraft }
                }
            }
            // Empty roots receive schema 1 only after an actual edit. Imported
            // unsupported/missing versions are not silently repaired.
            if !root.isEmpty { guard root["schemaVersion"]?.integer == 1 else { throw ProjectEditError.invalidDraft } }
            if let value = root["stateEnabled"], value != .null {
                guard case .bool(let enabled) = value else { throw ProjectEditError.invalidDraft }
                stateEnabled = enabled
            }
            if let source = root["attributes"] {
                guard let array = source.array, array.count <= 32 else { throw ProjectEditError.invalidDraft }
                var seen = Set<String>()
                rows = try array.map { value in
                    guard let fields = value.object, let key = fields["key"]?.text,
                          Self.validKey(key), seen.insert(key).inserted,
                          let label = fields["label"]?.text else { throw ProjectEditError.invalidDraft }
                    let flag = key.hasPrefix("clue.") || key.hasPrefix("tag.")
                    func number(_ field: String, _ fallback: Int) throws -> String {
                        guard let raw = fields[field] else { return String(fallback) }
                        guard let value = raw.integer, (-2147483648...2147483647).contains(value) else { throw ProjectEditError.invalidDraft }
                        return String(value)
                    }
                    let visible: Bool
                    if let value = fields["visible"] {
                        guard case .bool(let flag) = value else { throw ProjectEditError.invalidDraft }; visible = flag
                    } else { visible = true }
                    let row = try Row(id: UUID(), key: key, label: label, initial: number("initial", 0),
                        minimum: number("min", flag ? 0 : -10000), maximum: number("max", flag ? 1 : 10000),
                        visible: visible, existingKey: key, source: fields)
                    _ = try Self.values(row); return row
                }
            }
            originalRows = rows; originalEnabled = stateEnabled
        } catch { readOnly = true; rows = []; originalRows = [] }
    }
    public mutating func setStateEnabled(_ value: Bool) { guard !readOnly else { return }; stateEnabled = value }
    @discardableResult public mutating func add() -> UUID? {
        guard !readOnly, rows.count < 32 else { return nil }
        let row = Row(id: UUID(), key: "counter.", label: "", initial: "0", minimum: "-10000", maximum: "10000",
                      visible: true, existingKey: nil, source: nil)
        rows.append(row); return row.id
    }
    @discardableResult public mutating func replace(_ row: Row) -> Bool {
        guard !readOnly, let index = rows.firstIndex(where: { $0.id == row.id }),
              row.existingKey == rows[index].existingKey else { return false }
        if let key = rows[index].existingKey, !key.utf8.elementsEqual(row.key.utf8) { return false }
        // Preserve the original payload even if a caller supplies a foreign Row.
        var next = rows[index]
        next.key = row.key; next.label = row.label; next.initial = row.initial
        next.minimum = row.minimum; next.maximum = row.maximum; next.visible = row.visible
        rows[index] = next; return true
    }
    @discardableResult public mutating func remove(_ id: UUID) -> Bool {
        guard !readOnly, let index = rows.firstIndex(where: { $0.id == id }) else { return false }
        rows.remove(at: index); return true
    }
    public var isUnchanged: Bool {
        !readOnly && stateEnabled == originalEnabled && rows.count == originalRows.count &&
        zip(rows, originalRows).allSatisfy { Self.same($0.0, $0.1) }
    }
    public var isValid: Bool { (try? validatedRows()) != nil }
    public func serialized(matching source: ProjectEditJSON?) throws -> ProjectEditJSON? {
        guard !readOnly, try Self.bytes(raw) == Self.bytes(source) else { throw ProjectEditError.invalidDraft }
        if isUnchanged { return raw }
        let attributes = try validatedRows()
        var next = root
        if next.isEmpty { next["schemaVersion"] = .number(1) }
        let sameRows = rows.count == originalRows.count && zip(rows, originalRows).allSatisfy { Self.same($0.0, $0.1) }
        if !sameRows { next["attributes"] = .array(attributes) }
        if stateEnabled != originalEnabled { next["stateEnabled"] = .bool(stateEnabled) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(ProjectEditJSON.object(next))
        guard data.count <= 16 * 1024 else { throw ProjectEditError.invalidDraft }
        return .string(String(decoding: data, as: UTF8.self))
    }
    private func validatedRows() throws -> [ProjectEditJSON] {
        guard !readOnly, rows.count <= 32 else { throw ProjectEditError.invalidDraft }
        var seen = Set<String>()
        return try rows.map { row in
            guard Self.validKey(row.key), seen.insert(row.key).inserted,
                  row.existingKey.map({ $0.utf8.elementsEqual(row.key.utf8) }) ?? true else { throw ProjectEditError.invalidDraft }
            let values = try Self.values(row)
            var result = row.source ?? [:]
            let original = originalRows.first { $0.id == row.id }
            if original == nil { result["key"] = .string(row.key) }
            if original == nil || !row.label.utf8.elementsEqual(original!.label.utf8) { result["label"] = .string(row.label) }
            if original == nil || Self.inputInteger(row.initial) != Self.inputInteger(original!.initial) { result["initial"] = .number(Decimal(values.initial)) }
            if original == nil || Self.inputInteger(row.minimum) != Self.inputInteger(original!.minimum) { result["min"] = .number(Decimal(values.minimum)) }
            if original == nil || Self.inputInteger(row.maximum) != Self.inputInteger(original!.maximum) { result["max"] = .number(Decimal(values.maximum)) }
            if original == nil || row.visible != original!.visible { result["visible"] = .bool(row.visible) }
            return .object(result)
        }
    }
    private static func values(_ row: Row) throws -> (initial: Int, minimum: Int, maximum: Int) {
        let label = javaTrim(row.label)
        guard !label.isEmpty, label.utf16.count <= 24,
              let initial = inputInteger(row.initial), let minimum = inputInteger(row.minimum), let maximum = inputInteger(row.maximum),
              minimum >= -10000, maximum <= 10000, minimum <= maximum, (minimum...maximum).contains(initial),
              !row.isFlag || (minimum == 0 && maximum == 1) else { throw ProjectEditError.invalidDraft }
        return (initial, minimum, maximum)
    }
    private static func same(_ lhs: Row, _ rhs: Row) -> Bool {
        lhs.id == rhs.id && lhs.key.utf8.elementsEqual(rhs.key.utf8) && lhs.label.utf8.elementsEqual(rhs.label.utf8) &&
        inputInteger(lhs.initial) != nil && inputInteger(lhs.initial) == inputInteger(rhs.initial) &&
        inputInteger(lhs.minimum) != nil && inputInteger(lhs.minimum) == inputInteger(rhs.minimum) &&
        inputInteger(lhs.maximum) != nil && inputInteger(lhs.maximum) == inputInteger(rhs.maximum) && lhs.visible == rhs.visible
    }
    private static func validKey(_ key: String) -> Bool {
        key.range(of: "^(clue|relation|tag|counter)\\.[a-z][a-z0-9_]{0,47}$(?![\\s\\S])", options: .regularExpression) != nil
    }
    private static func inputInteger(_ text: String) -> Int? {
        let value = javaTrim(text)
        guard value.range(of: "^-?[0-9]+$(?![\\s\\S])", options: .regularExpression) != nil else { return nil }
        return Int(value)
    }
    private static func javaTrim(_ text: String) -> String {
        var scalars = text.unicodeScalars[...]
        while let first = scalars.first, first.value <= 0x20 { scalars = scalars.dropFirst() }
        while let last = scalars.last, last.value <= 0x20 { scalars = scalars.dropLast() }
        return String(String.UnicodeScalarView(scalars))
    }
    private static func bytes(_ value: ProjectEditJSON?) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value.map { ["raw": $0] } ?? [:])
    }

    /// ProjectEditJSON's Decimal representation intentionally equates 1 and 1.0.
    /// Jackson's attribute contract does not: reject floating/exponent tokens at
    /// the three known integer fields before decoding can erase that distinction.
    private static func validateIntegerTokens(_ text: String) throws {
        var scanner = IntegerTokens(bytes: Array(text.utf8))
        try scanner.value(path: [])
    }
    private struct IntegerTokens {
        let bytes: [UInt8]
        var index = 0
        mutating func space() { while index < bytes.count && [9,10,13,32].contains(bytes[index]) { index += 1 } }
        mutating func string() throws -> String {
            let start = index; index += 1
            while index < bytes.count {
                let next = bytes[index]; index += 1
                if next == 92 { index += 1 }
                else if next == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
            }
            throw ProjectEditError.invalidDraft
        }
        // Grammar, size, nesting and duplicate keys were already checked by envelope.
        mutating func value(path: [String]) throws {
            space(); guard index < bytes.count else { throw ProjectEditError.invalidDraft }
            switch bytes[index] {
            case 123:
                index += 1; space()
                if bytes[index] == 125 { index += 1; return }
                while true {
                    space(); let key = try string(); space(); index += 1
                    try value(path: path + [key]); space()
                    if bytes[index] == 125 { index += 1; return }; index += 1
                }
            case 91:
                index += 1; space()
                if bytes[index] == 93 { index += 1; return }
                while true {
                    try value(path: path + ["[]"]); space()
                    if bytes[index] == 93 { index += 1; return }; index += 1
                }
            case 34: _ = try string()
            default:
                let start = index
                while index < bytes.count && ![9,10,13,32,44,93,125].contains(bytes[index]) { index += 1 }
                if path.count == 3, path[0] == "attributes", path[1] == "[]", ["initial","min","max"].contains(path[2]) {
                    let token = String(decoding: bytes[start..<index], as: UTF8.self)
                    guard Self.integerToken(token) else { throw ProjectEditError.invalidDraft }
                }
            }
        }
        private static func integerToken(_ token: String) -> Bool {
            token.range(of: "^-?[0-9]+$(?![\\s\\S])", options: .regularExpression) != nil
        }
    }
}
