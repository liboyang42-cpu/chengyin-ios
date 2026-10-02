import Foundation

public struct WalkingNavigationProgress: Equatable {
    public let fraction: Double
    public let remainingMeters: Double
    public let remainingSeconds: Double?
    public let stepIndex: Int?
    public let distanceFromRouteMeters: Double
    public let nearDestination: Bool

    /// Foreground best-effort geometric progress, not lane guidance or a gameplay predicate.
    /// Uses the provider's routed distance and step lengths, never a straight line as a route.
    public static func estimate(route: SearchRoutePreview, fix: RoamDeviceFix, destination: RoamCoordinate) -> Self? {
        guard !route.isStraightLine, route.coordinates.count >= 2, route.distanceMeters > 0 else { return nil }
        let points = route.coordinates
        let lengths = zip(points, points.dropFirst()).map { SearchRoutePreview.distance($0, $1) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return nil }
        var best = Double.infinity, along = 0.0, traversed = 0.0
        let latitudeScale = 111_195.0
        let longitudeScale = latitudeScale * max(0.00001, abs(cos(fix.coordinate.latitude * .pi / 180)))
        for index in lengths.indices {
            func offset(_ point: RoamCoordinate) -> (Double, Double) {
                var longitude = point.longitude - fix.coordinate.longitude
                if longitude > 180 { longitude -= 360 }; if longitude < -180 { longitude += 360 }
                return (longitude * longitudeScale, (point.latitude - fix.coordinate.latitude) * latitudeScale)
            }
            let a = offset(points[index]), b = offset(points[index + 1])
            let dx = b.0 - a.0, dy = b.1 - a.1, square = dx * dx + dy * dy
            let t = square > 0 ? min(1, max(0, -(a.0 * dx + a.1 * dy) / square)) : 0
            let distance = hypot(a.0 + t * dx, a.1 + t * dy)
            if distance < best { best = distance; along = traversed + lengths[index] * t }
            traversed += lengths[index]
        }
        let fraction = min(1, max(0, along / total))
        var stepIndex: Int?, stepDistance = 0.0
        for (index, step) in route.steps.enumerated() {
            stepDistance += step.distanceMeters
            if stepIndex == nil, fraction * route.distanceMeters < stepDistance { stepIndex = index }
        }
        if stepIndex == nil { stepIndex = route.steps.indices.last }
        // Near-destination is only a prompt to open the existing validation flow.
        let near = fraction >= 0.95 && SearchRoutePreview.distance(fix.coordinate, destination) <= 20 && fix.accuracyMeters <= 20
        return .init(fraction: fraction, remainingMeters: route.distanceMeters * (1 - fraction),
                     remainingSeconds: route.etaSeconds.map { $0 * (1 - fraction) }, stepIndex: stepIndex,
                     distanceFromRouteMeters: best, nearDestination: near)
    }
}
