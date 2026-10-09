import Foundation

/// The route/map-node ID and associated topic ID belong to different domains.
/// An absent topicId must not fall back to id, nodeId, a title or coordinates.
public struct RoamRouteTopicDestination: Equatable, Hashable {
    public let routeID: Int
    public let topicID: Int
    public init?(route: RoamRouteNode) {
        guard route.id > 0, let topicID = route.topicId, topicID > 0 else { return nil }
        routeID = route.id; self.topicID = topicID
    }
}

/// One explicit route-summary action. Reuses the existing Roam read/lifecycle
/// scope, and produces only a topic reference, never a synthetic RoamEvent.
public struct RoamRouteTopicNavigationSelection: Identifiable, Hashable {
    public let id = UUID()
    public let destination: RoamRouteTopicDestination
    private let origin: RoamEventNavigationScope
    public init?(route: RoamRouteNode, currentRoute: RoamRouteNode?, rendered: RoamEventNavigationScope?, current: RoamEventNavigationScope?) {
        guard route == currentRoute, let rendered, rendered == current,
              let destination = RoamRouteTopicDestination(route: route) else { return nil }
        self.destination = destination; origin = rendered
    }
    public func mayRemainOpen(in current: RoamEventNavigationScope?) -> Bool {
        guard let current else { return false }
        // Normal navigation retires the overview presentation only. Permission,
        // session, approved manual-area identity and reader replacement still fence.
        return origin.readerID == current.readerID && origin.identity == current.identity && origin.area == current.area
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
