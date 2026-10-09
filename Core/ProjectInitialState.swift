import Foundation

/// First-chapter UI for the existing topic-level journeyRules. Never edits thought/attribute definitions.
public struct ProjectInitialState {
    public enum Kind: String, CaseIterable, Hashable { case hp, luck }
    public struct Resource: Equatable {
        public var enabled: Bool
        public var initial: String
        public var maximum: String
    }
    public struct RecoveryChange: Identifiable, Equatable {
        public let key: String
        public let before: Int
        public let after: Int
        public var id: String { key }
    }
    public private(set) var readOnly = false
    public var hp = Resource(enabled: false, initial: "10", maximum: "10")
    public var luck = Resource(enabled: false, initial: "3", maximum: "3")
    private var originalHP = Resource(enabled: false, initial: "10", maximum: "10")
    private var originalLuck = Resource(enabled: false, initial: "3", maximum: "3")
    private let raw: ProjectEditJSON?
    private var root: [String: ProjectEditJSON] = [:]
    private static let recoveryDefaults = ["stationEndIfHurt": 2, "stageRestHpFloor": 6, "stageRestLuckFloor": 1, "exhaustRestHp": 5]
    public init(raw: ProjectEditJSON?) {
        self.raw = raw
        do {
            let fresh: Bool
            if raw == nil || raw == .null { fresh = true }
            else if let text = raw?.text {
                fresh = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !fresh {
                    let bytes = Data(text.utf8); guard bytes.count <= 16 * 1024 else { throw ProjectEditError.invalidDraft }
                    root = try ApprovedTopicReleaseWire.envelope(bytes)
                }
            } else { throw ProjectEditError.invalidDraft }
            if let version = root["schemaVersion"], version != .null, version.integer != 1 { throw ProjectEditError.invalidDraft }
            _ = try Self.boolean(root["stateEnabled"], fallback: false)
            if let attributes = root["attributes"], attributes != .null, attributes.array == nil { throw ProjectEditError.invalidDraft }
            hp = try Self.resource(root["hp"], fallback: .init(enabled: !fresh, initial: "10", maximum: "10"))
            luck = try Self.resource(root["luck"], fallback: .init(enabled: !fresh, initial: "3", maximum: "3"))
            let recovery = try Self.object(root["recovery"])
            for (key, fallback) in Self.recoveryDefaults { _ = try Self.integer(recovery[key], fallback: fallback) }
            originalHP = hp; originalLuck = luck
        } catch { readOnly = true }
    }
    public mutating func setEnabled(_ enabled: Bool, kind: Kind) {
        guard !readOnly else { return }
        switch kind {
        case .hp: if !enabled { hp = originalHP }; hp.enabled = enabled
        case .luck: if !enabled { luck = originalLuck }; luck.enabled = enabled
        }
    }
    private static func object(_ raw: ProjectEditJSON?) throws -> [String: ProjectEditJSON] {
        guard let raw, raw != .null else { return [:] }
        guard let object = raw.object else { throw ProjectEditError.invalidDraft }; return object
    }
    private static func boolean(_ raw: ProjectEditJSON?, fallback: Bool) throws -> Bool {
        guard let raw, raw != .null else { return fallback }
        guard case .bool(let value) = raw else { throw ProjectEditError.invalidDraft }; return value
    }
    private static func integer(_ raw: ProjectEditJSON?, fallback: Int) throws -> Int {
        guard let raw, raw != .null else { return fallback }
        guard let value = raw.integer else { throw ProjectEditError.invalidDraft }; return value
    }
    private static func resource(_ raw: ProjectEditJSON?, fallback: Resource) throws -> Resource {
        let object = try object(raw)
        return try .init(enabled: boolean(object["enabled"], fallback: fallback.enabled),
                         initial: String(integer(object["init"], fallback: Int(fallback.initial)!)),
                         maximum: String(integer(object["max"], fallback: Int(fallback.maximum)!)))
    }
    private static func same(_ lhs: Resource, _ rhs: Resource) -> Bool {
        lhs.enabled == rhs.enabled && Int(lhs.initial) == Int(rhs.initial) && Int(lhs.maximum) == Int(rhs.maximum)
    }
    public var isUnchanged: Bool { Self.same(hp, originalHP) && Self.same(luck, originalLuck) }
    private func values() throws -> (hpInitial: Int, hpMax: Int, luckInitial: Int, luckMax: Int) {
        guard !readOnly, let hpMax = Int(hp.maximum), (1...20).contains(hpMax),
              let hpInitial = Int(hp.initial), (1...hpMax).contains(hpInitial),
              let luckMax = Int(luck.maximum), (0...5).contains(luckMax),
              let luckInitial = Int(luck.initial), (0...luckMax).contains(luckInitial) else { throw ProjectEditError.invalidDraft }
        return (hpInitial, hpMax, luckInitial, luckMax)
    }
    private func recovery(values: (hpInitial: Int, hpMax: Int, luckInitial: Int, luckMax: Int)) throws -> [String: ProjectEditJSON] {
        var recovery = try Self.object(root["recovery"])
        for (key, fallback) in Self.recoveryDefaults {
            let old = try Self.integer(recovery[key], fallback: fallback)
            guard old >= 0 else { throw ProjectEditError.invalidDraft }
            recovery[key] = .number(Decimal(min(old, key == "stageRestLuckFloor" ? values.luckMax : values.hpMax)))
        }
        return recovery
    }
    public var recoveryChanges: [RecoveryChange] {
        guard !readOnly, !isUnchanged, let values = try? values(), let old = try? Self.object(root["recovery"]),
              let next = try? recovery(values: values) else { return [] }
        return Self.recoveryDefaults.keys.sorted().compactMap { key in
            guard let before = try? Self.integer(old[key], fallback: Self.recoveryDefaults[key]!),
                  let after = next[key]?.integer, before != after else { return nil }
            return .init(key: key, before: before, after: after)
        }
    }
    public func serialized(matching original: ProjectEditJSON?) throws -> ProjectEditJSON? {
        let sourceEncoder = JSONEncoder(); sourceEncoder.outputFormatting = [.sortedKeys]
        let sourceBytes = try sourceEncoder.encode(raw.map { ["raw": $0] } ?? [:])
        let currentBytes = try sourceEncoder.encode(original.map { ["raw": $0] } ?? [:])
        guard !readOnly, sourceBytes == currentBytes else { throw ProjectEditError.invalidDraft }
        if isUnchanged { return raw } // Opening, cancel and numeric no-op never normalize the imported string.
        let values = try values()
        var next = root, hpObject = try Self.object(root["hp"]), luckObject = try Self.object(root["luck"])
        hpObject["enabled"] = .bool(hp.enabled); hpObject["init"] = .number(Decimal(values.hpInitial)); hpObject["max"] = .number(Decimal(values.hpMax))
        luckObject["enabled"] = .bool(luck.enabled); luckObject["init"] = .number(Decimal(values.luckInitial)); luckObject["max"] = .number(Decimal(values.luckMax))
        next["hp"] = .object(hpObject); next["luck"] = .object(luckObject); next["schemaVersion"] = .number(1)
        next["stateEnabled"] = .bool(hp.enabled || luck.enabled || (root["stateEnabled"] == .bool(true) && root["attributes"]?.array?.isEmpty == false))
        next["recovery"] = .object(try recovery(values: values))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(ProjectEditJSON.object(next))
        guard bytes.count <= 16 * 1024 else { throw ProjectEditError.invalidDraft }
        return .string(String(decoding: bytes, as: UTF8.self))
    }
}
