import Foundation

/// Read-only server projection. This type cannot be constructed from creator
/// configuration and does not infer roles from names, member order or team IDs.
public struct JourneyRoleItem: Equatable, Identifiable {
    public let id: Int; public let label: String; public let text: String
}
public struct JourneyRoleContent: Equatable, Identifiable {
    public let roleID: String
    /// Server role label for this view (e.g. a character name); nil when not provided.
    public let label: String?
    public let title: String; public let body: String
    public let items: [JourneyRoleItem]
    public var id: String { roleID }
}
public struct JourneyRoleProjection: Equatable {
    /// Roles are 2–4 server ids A–D. SOLO is the merged full view (no team, self-play,
    /// one active member or an ambiguous team). `missing` is the legacy withheld reply.
    public enum Assignment: String, Equatable { case a = "A", b = "B", c = "C", d = "D", solo = "SOLO", missing }
    public static let roleIDs = ["A", "B", "C", "D"]
    public let nodeID: Int; public let runID: Int; public let stateVersion: Int
    public let assignment: Assignment; public let views: [JourneyRoleContent]
    /// Own role label for an assigned member; nil for SOLO or when not provided.
    public let roleLabel: String?
    public let otherRoleLabel: String?
    /// Every other role's label for an assigned member (empty for SOLO).
    public let otherRoleLabels: [String]
    public init?(encounter: PlayWireValue, expectedNodeID: Int) throws {
        guard encounter.object != nil else { throw PlayExperienceError.malformed }
        guard encounter["roleView"] != .null else { return nil }
        guard expectedNodeID > 0, let node = encounter["nodeId"].integer, node == expectedNodeID,
              let run = encounter["runId"].integer, run > 0,
              let version = encounter["stateVersion"].integer, version >= 0,
              let raw = encounter["roleView"].object,
              let rows = raw["views"]?.array else { throw PlayExperienceError.malformed }
        nodeID = node; runID = run; stateVersion = version
        if let missing = raw["roleMissing"], missing.bool == nil { throw PlayExperienceError.malformed }
        if raw["roleMissing"]?.bool == true {
            // A contradictory response never exposes either side, even when it includes content.
            guard rows.isEmpty, raw["role"] == nil || raw["role"] == .null else { throw PlayExperienceError.malformed }
            assignment = .missing; views = []; roleLabel = nil; otherRoleLabel = nil; otherRoleLabels = []; return
        }
        guard let role = raw["role"]?.text, let assignment = Assignment(rawValue: role), assignment != .missing else { throw PlayExperienceError.malformed }
        guard assignment == .solo ? (2...Self.roleIDs.count).contains(rows.count) : rows.count == 1 else { throw PlayExperienceError.malformed }
        func text(_ value: PlayWireValue?, required: Bool = false) throws -> String {
            if value == nil || value == .null { guard !required else { throw PlayExperienceError.malformed }; return "" }
            guard let value = value?.text, value.utf16.count <= 200,
                  !required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlayExperienceError.malformed }
            return value
        }
        func label(_ value: PlayWireValue?) throws -> String? {
            let value = try text(value).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        var parsed: [JourneyRoleContent] = []
        var ids = Set<String>()
        for row in rows {
            guard let fields = row.object, let id = fields["roleId"]?.text, Self.roleIDs.contains(id), ids.insert(id).inserted else { throw PlayExperienceError.malformed }
            let items: [PlayWireValue]
            if fields["items"] == nil || fields["items"] == .null { items = [] }
            else { guard let array = fields["items"]?.array, array.count <= 8 else { throw PlayExperienceError.malformed }; items = array }
            var details: [JourneyRoleItem] = []
            for (index, item) in items.enumerated() {
                guard let values = item.object else { throw PlayExperienceError.malformed }
                details.append(.init(id: index, label: try text(values["label"], required: true), text: try text(values["text"], required: true)))
            }
            parsed.append(.init(roleID: id, label: try label(fields["label"]), title: try text(fields["title"]), body: try text(fields["body"]), items: details))
        }
        if assignment != .solo { guard parsed.count == 1, ids == [role] else { throw PlayExperienceError.malformed } }
        self.assignment = assignment; views = parsed
        if assignment == .solo {
            roleLabel = nil; otherRoleLabel = nil; otherRoleLabels = []
        } else {
            roleLabel = try label(raw["roleLabel"]) ?? parsed[0].label
            otherRoleLabel = try label(raw["otherRoleLabel"])
            var others: [String] = []
            if let list = raw["otherRoleLabels"], list != .null {
                guard let values = list.array, values.count < Self.roleIDs.count else { throw PlayExperienceError.malformed }
                for value in values { if let entry = try label(value) { others.append(entry) } }
            }
            otherRoleLabels = others.isEmpty ? (otherRoleLabel.map { [$0] } ?? []) : others
        }
    }
}
