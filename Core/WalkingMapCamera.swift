import Foundation

/// Ephemeral presentation only. Camera actions never acquire location or route data.
public enum WalkingMapCamera {
    public enum Action: Equatable { case route, target }
    /// Exact authorized input plus an attempt revision. Equal coordinates alone cannot
    /// revive a button rendered before cancel/resume or route replacement.
    public struct Snapshot: Equatable {
        let revision: UUID
        let ownerNamespace: String
        public let target: AuthorizedWalkingTarget
        public let route: SearchRoutePreview
    }
    /// Retention is separate from route availability. The same authorized target can
    /// keep a manual viewport while a new route is loading, only until its lease ends.
    public struct Scope: Equatable {
        public struct Identity: Hashable {
            let ownerNamespace: String
            let reference: WalkingTargetReference
            let coordinate: WalkingCoordinate
            let authorityRevision: String
            let releaseID: String?
        }
        public let identity: Identity
        public let id: UUID
        let expiresAt: Date
        init(ownerNamespace: String, target: AuthorizedWalkingTarget, retaining previous: Scope? = nil, now: Date) {
            identity = Identity(ownerNamespace: ownerNamespace, reference: target.reference,
                coordinate: target.coordinate, authorityRevision: target.authorityRevision, releaseID: target.releaseID)
            expiresAt = target.expiresAt
            if let previous, previous.identity == identity, previous.expiresAt > now { id = previous.id }
            else { id = UUID() }
        }
    }
    public struct Gate {
        public struct Request {
            fileprivate let revision: UUID
            fileprivate let snapshot: Snapshot
            fileprivate let fit: MapMarkerDensity.Fit
        }
        private var revision = UUID()
        public init() {}
        public mutating func invalidate() { revision = UUID() }
        public func request(_ action: Action, snapshot: Snapshot?) -> Request? {
            guard let snapshot else { return nil }
            let points: [RoamCoordinate]
            switch action {
            case .route: points = snapshot.route.coordinates + [snapshot.target.coordinate.point]
            case .target: points = [snapshot.target.coordinate.point]
            }
            // Shared bounded camera geometry: no datum conversion or invented fallback.
            guard let fit = MapMarkerDensity.fit(points.map {
                .init(latitude: $0.latitude, longitude: $0.longitude)
            }) else { return nil }
            return Request(revision: revision, snapshot: snapshot, fit: fit)
        }
        public mutating func consume(_ request: Request, current: Snapshot?) -> MapMarkerDensity.Fit? {
            guard request.revision == revision else { return nil }
            invalidate()
            guard request.snapshot == current else { return nil }
            return request.fit
        }
    }
}
