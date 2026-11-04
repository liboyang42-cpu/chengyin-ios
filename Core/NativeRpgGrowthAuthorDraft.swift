import Foundation

/// Only edits growth inside the existing schema2 journeyRules string. No role creation, XP grant or network writer.
public struct NativeRpgGrowthAuthorDraft: Equatable {
    public enum Failure: Error { case unsupportedSource, invalidGrowth, sourceChanged }
    public let original: ProjectEditJSON
    private let rules: [String: ProjectEditJSON]
    private let originalGrowth: [String: ProjectEditJSON]?
    public private(set) var growth: [String: ProjectEditJSON]?
    public static let formalThresholds = [100,250,450,700,1000,1350,1750,2200,2700]
    public static let featKeys = ["brisk","keen_eye","silver_tongue","iron_stomach","lucky","photographic_memory"]
    public init(original: ProjectEditJSON?) throws {
        guard case .string(let raw)? = original, raw.utf8.count <= 1_048_576 else { throw Failure.unsupportedSource }
        let rules = try Self.originalFields(raw)
        guard rules["schemaVersion"] == .number(2),
              rules["growth"] == nil || rules["growth"]?.object != nil else { throw Failure.unsupportedSource }
        self.original = .string(raw); self.rules = rules; growth = rules["growth"]?.object; originalGrowth = growth
    }
    public var roleEnabled: Bool { rules["role"]?.object?["enabled"] == .bool(true) }
    public var changed: Bool { growth != originalGrowth }
    public mutating func useFormalCurve() {
        var next = growth ?? [:]
        next["maxLevel"] = .number(10); next["skillPointsPerLevel"] = .number(1)
        next["xpThresholds"] = .array(Self.formalThresholds.map { .number(Decimal($0)) })
        // This is an explicit author choice, but it still does not silently enable role or growth.
        if next["enabled"] == nil { next["enabled"] = .bool(false) }
        growth = next
    }
    public mutating func set(_ key: String, _ value: ProjectEditJSON) {
        guard ["enabled","maxLevel","skillPointsPerLevel","xpThresholds","feats"].contains(key), growth != nil else { return }; growth?[key] = value
    }
    public mutating func threshold(_ index: Int, value: String) {
        guard var rows = growth?["xpThresholds"]?.array, rows.indices.contains(index) else { return }
        rows[index] = NativeAuthorNumericInput.numberInput(value); growth?["xpThresholds"] = .array(rows)
    }
    public mutating func addThreshold() {
        guard var rows = growth?["xpThresholds"]?.array, rows.count < 19 else { return }
        rows.append(.string("")); growth?["xpThresholds"] = .array(rows)
    }
    public mutating func removeLastThreshold() {
        guard var rows = growth?["xpThresholds"]?.array, !rows.isEmpty else { return }; rows.removeLast(); growth?["xpThresholds"] = .array(rows)
    }
    public func serialized() throws -> ProjectEditJSON {
        // A cancelled/reverted edit must not normalize the original string or invent absent defaults.
        guard changed else { return original }
        guard let growth, Set(growth.keys).isSubset(of: Set(["enabled","maxLevel","skillPointsPerLevel","xpThresholds","feats"])),
              case .bool(let enabled)? = growth["enabled"], !enabled || roleEnabled,
              let max = growth["maxLevel"]?.integer, (1...20).contains(max),
              let points = growth["skillPointsPerLevel"]?.integer, (0...1_000_000).contains(points),
              let rows = growth["xpThresholds"]?.array, rows.count == max - 1 else { throw Failure.invalidGrowth }
        var previous = 0
        for row in rows { guard let threshold = row.integer, threshold > previous, threshold <= 1_000_000_000 else { throw Failure.invalidGrowth }; previous = threshold }
        if let raw = growth["feats"] {
            guard let rows = raw.array, rows.count <= 6 else { throw Failure.invalidGrowth }
            let values = rows.compactMap(\.text)
            guard values.count == rows.count, Set(values).count == values.count, Set(values).isSubset(of: Set(Self.featKeys)) else { throw Failure.invalidGrowth }
        }
        var next = rules; next["growth"] = .object(growth)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(ProjectEditJSON.object(next))
        guard bytes.count <= 1_048_576, let json = String(data: bytes, encoding: .utf8) else { throw Failure.invalidGrowth }; return .string(json)
    }
    public func applying(to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard let current = draft.preserved["journeyRules"]?.text, let source = original.text,
              current.utf8.elementsEqual(source.utf8) else { throw Failure.sourceChanged }
        guard changed else { return draft }
        var next = draft; next.preserved["journeyRules"] = try serialized(); return next
    }
    /// Reject duplicate or Unicode-equivalent keys before Foundation can collapse original declarations.
    /// This only refuses ambiguous input; it does not normalize, repair or supply any growth value.
    private static func originalFields(_ text: String) throws -> [String: ProjectEditJSON] {
        func uniqueKeys(_ value: ContentDraftJSON) throws {
            switch value {
            case .object(let fields):
                var seen = Set<String>()
                for (bytes, child) in fields {
                    guard let key = String(data: bytes, encoding: .utf8), seen.insert(key).inserted else { throw Failure.unsupportedSource }
                    try uniqueKeys(child)
                }
            case .array(let values): for child in values { try uniqueKeys(child) }
            default: break
            }
        }
        do {
            try uniqueKeys(ContentDraftJSON.parse(text))
            guard let fields = try JSONDecoder().decode(ProjectEditJSON.self, from: Data(text.utf8)).object else { throw Failure.unsupportedSource }
            return fields
        } catch { throw Failure.unsupportedSource }
    }
}
