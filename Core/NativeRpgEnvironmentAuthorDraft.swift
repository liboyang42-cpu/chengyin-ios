import Foundation

/// Edits only the original schema2 module switches; provider credentials and runtime facts have no input here.
public struct NativeRpgEnvironmentAuthorDraft: Equatable {
    public enum Failure: Error { case unsupported, changed, invalid }
    public let original: ProjectEditJSON
    public private(set) var rules: [String: ProjectEditJSON]
    public init(original: ProjectEditJSON?) throws {
        guard case .string(let text)? = original, text.utf8.count <= 1_048_576 else { throw Failure.unsupported }
        let rules = try Self.originalFields(text)
        guard rules["schemaVersion"] == .number(2),
              rules["env"] == nil || rules["env"]?.object != nil,
              rules["location"] == nil || rules["location"]?.object != nil else { throw Failure.unsupported }
        self.original = .string(text); self.rules = rules
    }
    public var enabled: Bool { rules["env"]?.object?["enabled"] == .bool(true) }
    public var authorOverride: Bool { rules["env"]?.object?["authorOverride"] == .bool(true) }
    public var locationEnabled: Bool { rules["location"]?.object?["enabled"] == .bool(true) }
    public mutating func configure(enabled: Bool, authorOverride: Bool, location: Bool) {
        var env = rules["env"]?.object ?? [:]
        env["enabled"] = .bool(enabled); env["authorOverride"] = .bool(authorOverride); rules["env"] = .object(env)
        var place = rules["location"]?.object ?? [:]; place["enabled"] = .bool(location); rules["location"] = .object(place)
    }
    public func applying(to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard let raw = draft.preserved["journeyRules"]?.text, let source = original.text, raw.utf8.elementsEqual(source.utf8) else { throw Failure.changed }
        guard let env = rules["env"]?.object, Set(env.keys).isSubset(of: ["enabled", "authorOverride", "cacheMinutes", "provider"]),
              case .bool? = env["enabled"], case .bool? = env["authorOverride"],
              let location = rules["location"]?.object, Set(location.keys) == Set(["enabled"]), case .bool? = location["enabled"] else { throw Failure.invalid }
        if let text = original.text, let originalRules = try? JSONDecoder().decode(ProjectEditJSON.self, from: Data(text.utf8)),
           let bytes = ProjectEditPendingMaterials.exactData(originalRules),
           ProjectEditPendingMaterials.exactData(ProjectEditJSON.object(rules)) == bytes { return draft }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ProjectEditJSON.object(rules))
        guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8) else { throw Failure.invalid }
        var next = draft; next.preserved["journeyRules"] = .string(text); return next
    }
    /// Reject duplicate or Unicode-equivalent keys before Foundation can collapse original declarations.
    /// This only refuses ambiguous input; it does not normalize, repair or supply any environment value.
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
