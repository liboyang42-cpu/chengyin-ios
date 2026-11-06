import Foundation

/// Patch only original schema2 journeyRules passive/checkEnabled/tiers.dc; preserve all original role/attribute definitions.
public struct NativeRpgPassiveRulesDraft: Equatable {
    public enum Failure: Error { case unsupported, invalid, changed }
    public let original: ProjectEditJSON
    public private(set) var rules: [String: ProjectEditJSON]
    public init(original: ProjectEditJSON?) throws {
        guard case .string(let text)? = original, text.utf8.count <= 1_048_576 else { throw Failure.unsupported }
        let value = try Self.originalFields(text)
        guard value["schemaVersion"] == .number(2),
              value["passive"] == nil || value["passive"]?.object != nil,
              value["tiers"] == nil || value["tiers"]?.object != nil else { throw Failure.unsupported }
        self.original = .string(text); rules = value
    }
    public var enabled: Bool { rules["passive"]?.object?["enabled"] == .bool(true) }
    public var checksEnabled: Bool { rules["checkEnabled"] == .bool(true) }
    public var roleEnabled: Bool { rules["role"]?.object?["enabled"] == .bool(true) }
    public var skills: [ProjectEditJSON] { (rules["role"]?.object?["skills"]?.array ?? []).filter { $0.object?["category"] == .string("OBS") } }
    public var base: Int? { rules["passive"]?.object?["base"]?.integer }
    public mutating func checkEnabled(_ value: Bool) { rules["checkEnabled"] = .bool(value) }
    public mutating func enabled(_ value: Bool) {
        var fields = rules["passive"]?.object ?? [:]; fields["enabled"] = .bool(value); rules["passive"] = .object(fields)
    }
    public mutating func useFormalBase() {
        var fields = rules["passive"]?.object ?? ["enabled": .bool(false)]; fields["base"] = .number(10); rules["passive"] = .object(fields)
    }
    public func dc(_ tier: String) -> String { NativeAuthorNumericInput.display(rules["tiers"]?.object?[tier]?.object?["dc"]) }
    public mutating func dc(_ tier: String, _ text: String) {
        guard ["easy","medium","hard"].contains(tier) else { return }
        var tiers = rules["tiers"]?.object ?? [:], row = tiers[tier]?.object ?? [:]
        row["dc"] = NativeAuthorNumericInput.numberInput(text); tiers[tier] = .object(row); rules["tiers"] = .object(tiers)
    }
    public mutating func useFormalDCs() { for (tier, dc) in zip(["easy","medium","hard"],[10,13,16]) { self.dc(tier,String(dc)) } }
    public var issues: [String] {
        var values: [String] = []
        if enabled && (!checksEnabled || !roleEnabled || skills.isEmpty) { values.append("启用被动观察需要本版本原检定、角色和真实 OBS 技能；不会自动创建或启用它们") }
        guard let passive = rules["passive"]?.object, Set(passive.keys).isSubset(of: ["enabled","base"]),
              case .bool? = passive["enabled"], let base, (0...1_000_000).contains(base) else { return values + ["原被动配置缺失或格式无效；可明确选择正式基础值10"] }
        var previous = 4
        guard let tiers = rules["tiers"]?.object, Set(tiers.keys).isSubset(of: ["easy","medium","hard"]) else { return values + ["原难度表缺失或含未知字段"] }
        for tier in ["easy","medium","hard"] {
            guard let row = tiers[tier]?.object, Set(row.keys).isSubset(of: ["dc","damage"]), let dc = row["dc"]?.integer,
                  (5...25).contains(dc), dc > previous else { return values + ["三档 DC 必须5至25且严格递增"] }
            previous = dc
        }
        return values
    }
    public func serialized() throws -> ProjectEditJSON {
        guard issues.isEmpty else { throw Failure.invalid }
        if let text = original.text, let originalRules = try? JSONDecoder().decode(ProjectEditJSON.self, from: Data(text.utf8)),
           let bytes = ProjectEditPendingMaterials.exactData(originalRules),
           ProjectEditPendingMaterials.exactData(ProjectEditJSON.object(rules)) == bytes { return original }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(ProjectEditJSON.object(rules)); guard bytes.count <= 1_048_576, let text = String(data: bytes,encoding: .utf8) else { throw Failure.invalid }
        return .string(text)
    }
    public func applying(to current: ProjectEditDraft) throws -> ProjectEditDraft {
        guard let raw = current.preserved["journeyRules"]?.text, let source = original.text, raw.utf8.elementsEqual(source.utf8) else { throw Failure.changed }
        var next = current; next.preserved["journeyRules"] = try serialized(); return next
    }
    /// Reject duplicate or Unicode-equivalent keys before Foundation can collapse original declarations.
    /// This only refuses ambiguous input; it does not normalize, repair or supply any passive value.
    private static func originalFields(_ text: String) throws -> [String: ProjectEditJSON] {
        func uniqueKeys(_ value: ContentDraftJSON) throws {
            switch value {
            case .object(let fields):
                var seen = Set<String>()
                for (bytes, child) in fields {
                    guard let key = String(data: bytes, encoding: .utf8), seen.insert(key).inserted else { throw Failure.unsupported }
                    try uniqueKeys(child)
                }
            case .array(let values): for child in values { try uniqueKeys(child) }
            default: break
            }
        }
        do {
            try uniqueKeys(ContentDraftJSON.parse(text))
            guard let fields = try JSONDecoder().decode(ProjectEditJSON.self, from: Data(text.utf8)).object else { throw Failure.unsupported }
            return fields
        } catch { throw Failure.unsupported }
    }
}
