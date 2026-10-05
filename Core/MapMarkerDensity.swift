import Foundation

/// Presentation-only connected components in actual projected screen points.
/// Inputs must already be authorized by the caller. IDs are never business groups.
public enum MapMarkerDensity {
    public struct Point: Equatable {
        public let id: String
        public let x: Double
        public let y: Double
        public init(id: String, x: Double, y: Double) { self.id = id; self.x = x; self.y = y }
    }
    public static func groups(_ points: [Point], diameter: Double) -> [[String]] {
        guard diameter.isFinite, diameter > 0 else { return [] }
        // Ambiguous duplicate identities fail closed, rather than inflate a count.
        let counts = Dictionary(grouping: points, by: \.id)
        let valid = points.filter { !$0.id.isEmpty && $0.x.isFinite && $0.y.isFinite && counts[$0.id]?.count == 1 }
            .sorted { $0.id < $1.id }
        var remaining = valid
        var result: [[String]] = []
        while !remaining.isEmpty {
            var component = [remaining.removeFirst()]
            var cursor = 0
            while cursor < component.count {
                let point = component[cursor]
                let matches = remaining.filter { hypot($0.x - point.x, $0.y - point.y) < diameter }
                let ids = Set(matches.map(\.id))
                remaining.removeAll { ids.contains($0.id) }
                component.append(contentsOf: matches)
                cursor += 1
            }
            result.append(component.map(\.id).sorted())
        }
        return result
    }
    public struct Coordinate {
        public let latitude: Double
        public let longitude: Double
        public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    }
    public struct Target {
        public let id: String
        public let coordinate: Coordinate
        public init(id: String, coordinate: Coordinate) { self.id = id; self.coordinate = coordinate }
    }
    /// A view-lifetime gate for explicit camera actions. Replacing the input,
    /// leaving the view or consuming a request invalidates older button actions.
    /// It contains no location source, business selection or persistent state.
    public struct FocusGate {
        public struct Request {
            fileprivate let revision: UUID
            fileprivate let fit: Fit
        }
        private var revision = UUID()
        public init() {}
        public mutating func invalidate() { revision = UUID() }
        public func request(selectedID: String?, targets: [Target]) -> Request? {
            guard let selectedID, !selectedID.isEmpty else { return nil }
            let matches = targets.filter { $0.id == selectedID }
            guard matches.count == 1, let target = matches.first,
                  let fit = MapMarkerDensity.fit([target.coordinate]) else { return nil }
            return Request(revision: revision, fit: fit)
        }
        public mutating func consume(_ request: Request) -> Fit? {
            guard request.revision == revision else { return nil }
            invalidate()
            return request.fit
        }
    }
    public struct Fit: Equatable {
        public let latitude: Double
        public let longitude: Double
        public let latitudeSpan: Double
        public let longitudeSpan: Double
    }
    /// Bounded camera hints only; never transforms or persists business coordinates.
    /// Polar or date-line-spanning membership uses explicit list selection instead.
    public static func fit(_ points: [Coordinate]) -> Fit? {
        guard !points.isEmpty, points.allSatisfy({
            $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 85 && abs($0.longitude) <= 180
        }), let south = points.map(\.latitude).min(), let north = points.map(\.latitude).max(),
            let west = points.map(\.longitude).min(), let east = points.map(\.longitude).max(), east - west <= 180 else { return nil }
        let latitude = min(84.9995, max(-84.9995, (south + north) / 2))
        let longitude = (west + east) / 2
        let latitudeSpan = min(max(0.001, (north - south) * 1.5), 2 * (85 - abs(latitude)))
        let longitudeSpan = min(360, max(0.001, (east - west) * 1.5))
        return Fit(latitude: latitude, longitude: longitude, latitudeSpan: latitudeSpan, longitudeSpan: longitudeSpan)
    }

}
