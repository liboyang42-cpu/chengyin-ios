import Foundation

/// The existing activity read identity plus one successful gate response and UI
/// presentation. It contains no membership, registration or write authority.
public struct ActivityRequiredClubScope: Hashable {
    public let activityID: Int
    public let readerID: ObjectIdentifier
    public let identity: String
    public let readID: UUID
    public let presentationID: UUID
    public init?(activityID: Int, readerID: ObjectIdentifier, identity: String, readID: UUID?,
                 presentationID: UUID, isConfigured: Bool) {
        guard activityID > 0, !identity.isEmpty, let readID, isConfigured else { return nil }
        self.activityID = activityID; self.readerID = readerID; self.identity = identity
        self.readID = readID; self.presentationID = presentationID
    }
    fileprivate func sameRead(as other: Self) -> Bool {
        activityID == other.activityID && readerID == other.readerID && identity == other.identity && readID == other.readID
    }
}

/// Only an explicit clubRequired.clubID may open a read-only club profile.
/// The activity remains gated; no title/activity/owner ID can substitute.
public struct ActivityRequiredClubSelection: Identifiable, Hashable {
    public let id = UUID()
    public let clubID: Int
    private let gate: ActivityDetailAccess
    private let origin: ActivityRequiredClubScope
    public init?(access: ActivityDetailAccess, currentAccess: ActivityDetailAccess?,
                 rendered: ActivityRequiredClubScope?, current: ActivityRequiredClubScope?) {
        guard access == currentAccess, case .clubRequired(let clubID, _) = access,
              let clubID, clubID > 0, let rendered, rendered == current else { return nil }
        self.clubID = clubID; gate = access; origin = rendered
    }
    public func mayRemainOpen(access: ActivityDetailAccess?, in current: ActivityRequiredClubScope?) -> Bool {
        guard gate == access, let current else { return false }
        // A normal push retires overview callbacks only. A reread or scope change
        // still retires the accepted target, including an equal-payload reread.
        return origin.sameRead(as: current)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
