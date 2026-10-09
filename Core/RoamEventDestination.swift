import Foundation

/// Public event IDs retain their source domain. A theme/template/member ID never
/// substitutes for the exact `id` supplied by the activity/topic event projection.
public enum RoamEventDestination: Hashable {
    case activity(Int), topic(Int)
    public init?(event: RoamEvent) {
        guard event.isSupported else { return nil }
        switch event.kind {
        case "activity": self = .activity(event.sourceID)
        case "topic": self = .topic(event.sourceID)
        default: return nil
        }
    }
}

/// View lifetime and the existing read identity/area; no new read or write grant.
public struct RoamEventNavigationScope: Hashable {
    public let readerID: ObjectIdentifier
    public let identity: RoamReadIdentity
    public let area: RoamSearchArea
    public let presentationID: UUID
    public init?(readerID: ObjectIdentifier, identity: RoamReadIdentity?, area: RoamSearchArea?, presentationID: UUID, isConfigured: Bool) {
        guard isConfigured, let identity, identity.accountID > 0, let area else { return nil }
        self.readerID = readerID; self.identity = identity; self.area = area; self.presentationID = presentationID
    }
    fileprivate func sameAuthority(as other: Self) -> Bool {
        readerID == other.readerID && identity == other.identity && area == other.area
    }
}

/// Issued only by an explicit, exact-snapshot tap. Stable navigation may outlive
/// the overview's onDisappear; later account/lease/area changes still invalidate it.
public struct RoamEventNavigationSelection: Identifiable, Hashable {
    public let id = UUID()
    public let destination: RoamEventDestination
    private let origin: RoamEventNavigationScope
    public init?(event: RoamEvent, currentEvent: RoamEvent?, rendered: RoamEventNavigationScope?, current: RoamEventNavigationScope?) {
        guard event == currentEvent, let rendered, rendered == current,
              let destination = RoamEventDestination(event: event) else { return nil }
        self.destination = destination; origin = rendered
    }
    public func mayRemainOpen(in current: RoamEventNavigationScope?) -> Bool {
        guard let current else { return false }
        return origin.sameAuthority(as: current)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
