import Foundation

/// Existing topic-create/update fields only. Membership, invitations and ticket
/// team-size/pricing are separate contracts and are never modified here.
public struct ProjectTeamConfiguration {
    public enum Mode: Int, CaseIterable, Hashable { case off = 0, atRegistration = 1, afterRegistration = 2 }
    public static let fields = ["teamMode", "teamMaxMembers"]
    public private(set) var mode: Mode
    public private(set) var maximum: Int
    public let readOnly: Bool
    private let originalMode: Mode
    private let originalMaximum: Int
    private let sourceBytes: Data?

    public init(draft: ProjectEditDraft, baseline: ProjectEditSnapshot? = nil) {
        let mode = draft.preserved["teamMode"]?.integer.flatMap(Mode.init(rawValue:)) ?? .off
        let maximum = draft.preserved["teamMaxMembers"]?.integer ?? 4
        self.mode = mode; originalMode = mode; self.maximum = maximum; originalMaximum = maximum
        sourceBytes = ProjectEditPendingMaterials.exactData(draft)
        readOnly = !Self.canSubmit(draft, baseline: baseline)
    }
    public static func canSubmit(_ draft: ProjectEditDraft, baseline: ProjectEditSnapshot? = nil) -> Bool {
        // The current server normalizer applies these bounds to both products.
        // Unknown types/values are retained in the draft, never coerced to 0/4.
        for (key, bounds) in [("teamMode", 0...2), ("teamMaxMembers", 2...4)] {
            if let raw = draft.preserved[key], raw != .null {
                guard let integer = raw.integer, bounds.contains(integer) else { return false }
            }
        }
        // An old local envelope predating this field cannot erase fresh readback.
        // Reloading the current editor recovers it; do not infer a user change.
        if let baseline, baseline.topicID != nil {
            for key in fields where baseline.draft.preserved[key] != nil {
                if draft.preserved[key] == nil { return false }
            }
        }
        return true
    }
    public mutating func selectMode(_ value: Mode) { guard !readOnly else { return }; mode = value }
    public mutating func selectMaximum(_ value: Int) {
        guard !readOnly, (2...4).contains(value) else { return }; maximum = value
    }
    public func applying(to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard !readOnly, draft.product == .city, let sourceBytes,
              ProjectEditPendingMaterials.exactData(draft) == sourceBytes else { throw ProjectEditError.invalidDraft }
        var result = draft
        // Missing/null shapes and a change-and-return-to-original remain exact.
        if mode != originalMode { result.preserved["teamMode"] = .number(Decimal(mode.rawValue)) }
        if maximum != originalMaximum { result.preserved["teamMaxMembers"] = .number(Decimal(maximum)) }
        return result
    }
}
