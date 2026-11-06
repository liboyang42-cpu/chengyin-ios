import Foundation

/// Match the existing map-pin ordinal when a safe menu name is ambiguous.
/// This is display-only; node IDs and camera/navigation requests remain unchanged.
struct PlayRouteMapMenuLabels {
    private let ordinals: [Int: Int]
    init(presentation: PlayRouteMapPresentation) {
        let visible = presentation.stops.filter { $0.state != .locked }
        let groups = Dictionary(grouping: visible) { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        var values: [Int: Int] = [:]
        for group in groups.values where group.count > 1 {
            for stop in group { values[stop.id] = stop.order }
        }
        ordinals = values
    }
    func ordinal(for nodeID: Int) -> Int? { ordinals[nodeID] }
}
