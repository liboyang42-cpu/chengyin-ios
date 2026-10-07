import Foundation

/// A read-only city-orientation projection. It deliberately contains no story,
/// questions, answers, NPCs, user position, routing service or completion command.
public struct PlayRouteMapPresentation: Equatable {
    public struct Coordinate: Equatable {
        public let latitude: Double
        public let longitude: Double
        public init?(latitude: Double?, longitude: Double?) {
            guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
            self.latitude = latitude; self.longitude = longitude
        }
    }
    public enum State: String, Equatable {
        case current, completed, available, locked, unknown
        public var labelKey: String { "playRoute.state." + rawValue }
        public var symbol: String {
            switch self {
            case .current: return "flag.fill"
            case .completed: return "checkmark.circle.fill"
            case .available: return "circle"
            case .locked: return "lock.fill"
            case .unknown: return "questionmark.circle"
            }
        }
    }
    public struct Stop: Equatable, Identifiable {
        public let id: Int
        public let order: Int
        public let name: String?
        public let address: String?
        public let coordinate: Coordinate?
        public let state: State
        public var canOpen: Bool { state == .current || state == .completed }
    }
    public struct Segment: Equatable, Identifiable {
        public let id: Int
        public let start: Coordinate
        public let end: Coordinate
    }
    public let stops: [Stop]
    public let currentNodeID: Int?
    /// Dashed straight segments illustrate the response's node order only.
    /// Missing coordinates and restricted stops break the line; no gap is bridged.
    public let segments: [Segment]
    public var mappedStops: [Stop] { stops.filter { $0.coordinate != nil } }

    public init?(snapshot: PlaySnapshot) {
        guard PlayGameplayMode(serverValue: snapshot.result.mode) == .cityOrientation,
              snapshot.availability == .active || snapshot.availability == .completed else { return nil }
        let nodes = snapshot.visibleNodes
        let eligible = nodes.filter { !snapshot.isLocked($0) && !snapshot.isDone($0) && $0.done == false }
        let eligibleIDs = Set(eligible.map(\.id))
        let proposed = [snapshot.route?.currentNodeID, snapshot.route?.recommendedNodeID,
                        PlayTaskSummaryPresentation(snapshot: snapshot).currentNodeID]
        let currentID = snapshot.availability == .active ? proposed.compactMap { $0 }.first(where: eligibleIDs.contains) : nil
        currentNodeID = currentID
        stops = nodes.enumerated().map { offset, node in
            let locked = snapshot.isLocked(node)
            let state: State = locked ? .locked : snapshot.isDone(node) ? .completed :
                node.id == currentID ? .current : node.done == false ? .available : .unknown
            return Stop(id: node.id, order: offset + 1,
                        name: locked ? nil : node.name, address: locked ? nil : node.address,
                        coordinate: locked ? nil : Coordinate(latitude: node.latitude, longitude: node.longitude), state: state)
        }
        segments = zip(stops, stops.dropFirst()).compactMap { start, end in
            guard let a = start.coordinate, let b = end.coordinate else { return nil }
            return Segment(id: start.id, start: a, end: b)
        }
    }
}

/// A navigation receipt binds the exact displayed read AND coordinator lifetime.
/// Equality of node IDs, route versions or response bytes cannot revive old taps.
public struct PlayRouteMapSelection: Hashable, Identifiable {
    public let id: UUID
    private let nodeID: Int
    private let snapshot: PlaySnapshot
    private let context: PlayInteractionContext
    public init?(nodeID: Int, snapshot: PlaySnapshot, context: PlayInteractionContext?) {
        guard let context, context.authoritativeMode == .cityOrientation,
              PlayRouteMapPresentation(snapshot: snapshot)?.stops.contains(where: { $0.id == nodeID && $0.canOpen }) == true else { return nil }
        id = UUID(); self.nodeID = nodeID; self.snapshot = snapshot; self.context = context
    }
    public func resolve(snapshot: PlaySnapshot?, context: PlayInteractionContext?) -> Int? {
        guard context == self.context, snapshot == self.snapshot,
              let snapshot,
              PlayRouteMapPresentation(snapshot: snapshot)?.stops.contains(where: { $0.id == nodeID && $0.canOpen }) == true else { return nil }
        return nodeID
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
