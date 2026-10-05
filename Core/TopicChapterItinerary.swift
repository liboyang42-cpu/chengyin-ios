import Foundation

/// A reading aid for the stops already returned in one chapter, never a navigable route.
/// The preceding stop is always the immediately adjacent source row, including rows with
/// missing coordinates. We do not skip a hidden/unknown leg or join separate chapters.
public struct TopicChapterItinerary: Equatable {
    public struct Stop: Equatable, Identifiable {
        /// Source position preserves order and duplicate backend identifiers.
        public let id: Int
        public let node: TopicNode
        public let estimatedWalkingMinutes: Int?
    }

    public let stops: [Stop]
    public var hasWalkingEstimates: Bool { stops.contains { $0.estimatedWalkingMinutes != nil } }

    public init(chapter: TopicChapter) {
        stops = chapter.nodes.enumerated().map { index, node in
            Stop(id: index, node: node, estimatedWalkingMinutes: index > 0
                ? Self.walkingMinutes(from: chapter.nodes[index - 1], to: node) : nil)
        }
    }

    private static func coordinate(_ node: TopicNode) -> RoamCoordinate? {
        guard let latitude = node.latitude, let longitude = node.longitude,
              latitude != 0, longitude != 0 else { return nil }
        // Zero is an absent-coordinate sentinel in the topic source. Finite/range checks
        // additionally prevent malformed data from becoming a plausible walking estimate.
        return RoamCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func walkingMinutes(from previous: TopicNode, to current: TopicNode) -> Int? {
        guard let origin = coordinate(previous), let destination = coordinate(current) else { return nil }
        let meters = RoamExperienceMath.distanceMeters(origin, destination)
        guard meters.isFinite, meters > 0 else { return nil }
        // Source presentation uses an 80 m/min straight-line approximation. Stop dwell
        // time, challenge duration and chapter duration are deliberately not inputs.
        return max(1, Int((meters / 80).rounded()))
    }
}
