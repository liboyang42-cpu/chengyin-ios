import Foundation

/// Reasons the reviewed read contract cannot issue navigation authority. Field names are
/// requirements, not an assertion that these fields or a navigation endpoint exist today.
public enum WalkingTargetReadFailure: Error, Equatable {
    case unsupportedKind
    case missingEvidence([String])
}

/// Re-reads the exact source identity on every attempt/resume. No cached card, caller boolean,
/// inferred country, client timestamp or coordinate conversion can manufacture authority.
@MainActor public final class SourceWalkingTargetAuthorizer: WalkingTargetAuthorizing {
    private let reader: any SearchMapReading
    private let owner: RuntimeDependencyContext
    private let current: () -> RuntimeDependencyContext?
    private let scope: UUID
    private let nearbyArea: RoamSearchArea?
    public init(reader: any SearchMapReading, owner: RuntimeDependencyContext,
                nearbyArea: RoamSearchArea? = nil, current: @escaping () -> RuntimeDependencyContext?) {
        self.reader = reader; self.owner = owner; self.current = current
        self.scope = reader.scope; self.nearbyArea = nearbyArea
    }
    public func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        try checkCurrent()
        guard reference.isValid, reader.isConfigured, !reader.isOfflineExample else {
            throw WalkingNavigationFailure.targetUnavailable
        }
        switch reference.kind {
        case .cityNode:
            // City IDs are roam_poi.id (CityNodeVO.poiId), not merchant or registration IDs.
            let node: SearchMapCityNode
            do { node = try await reader.cityNode(id: reference.id) }
            catch {
                try checkCurrent()
                if error as? APIError == .businessCode(410) || error as? APIError == .httpStatus(410) {
                    throw WalkingNavigationFailure.targetUnavailable
                }
                throw error
            }
            try checkCurrent()
            guard node.poiID == reference.id, node.status == 1, node.coordinate != nil else {
                throw WalkingNavigationFailure.targetUnavailable
            }
            // Detail also returns status=0 historical reward records. HTTP success alone
            // therefore cannot establish that a target is currently open. The source mapper
            // also does not prove current joined-merchant public visibility.
            throw WalkingTargetReadFailure.missingEvidence([
                "publicVisibility", "coordinateDatum", "countryRegion", "authorityRevision",
                "navigationIssuedAt", "navigationExpiresAt"
            ])
        case .nearbyNode:
            guard let nearbyArea else { throw WalkingTargetReadFailure.missingEvidence(["nearbyQueryArea"]) }
            let result = try await reader.nearby(area: nearbyArea)
            try checkCurrent()
            let matches = result.nodes.filter { $0.id == reference.id }
            guard matches.count == 1, matches[0].coordinate != nil else {
                throw WalkingNavigationFailure.targetUnavailable
            }
            // NearbyNodeVO.id is cms_registration_merchant.id. Its nodeId/topicId
            // are different identities. The query excludes deletion but does not provide
            // player lock/visibility authority; never reinterpret this as a city POI read.
            throw WalkingTargetReadFailure.missingEvidence([
                "playerNavigationVisibility", "locked", "coordinateDatum", "countryRegion",
                "authorityRevision", "navigationExpiresAt"
            ])
        case .merchant, .storyNode:
            // Play nodes/route-state require their own activity/topic/session and release
            // binding. A missionID alone cannot select the reviewed read contract.
            throw WalkingTargetReadFailure.unsupportedKind
        }
    }
    private func checkCurrent() throws {
        try Task.checkCancellation()
        guard current() == owner, reader.scope == scope else { throw WalkingNavigationFailure.staleContext }
    }
}

/// A per-screen planner which reauthorizes the selected target before every provider read.
/// Cancellation invalidates in-flight work; reopening must get a fresh factory instance.
@MainActor public final class AuthorizedWalkingPreviewPlanner: SearchRoutePlanning {
    private let reference: WalkingTargetReference
    private let targets: any WalkingTargetAuthorizing
    private let planner: any SearchRoutePlanning
    private let current: () -> Bool
    private let now: () -> Date
    private var cancelled = false
    public init(reference: WalkingTargetReference, targets: any WalkingTargetAuthorizing,
                planner: any SearchRoutePlanning, current: @escaping () -> Bool,
                now: @escaping () -> Date = Date.init) {
        self.reference = reference; self.targets = targets; self.planner = planner
        self.current = current; self.now = now
    }
    public func preview(_ request: SearchRouteRequest) async throws -> SearchRoutePreview {
        try checkCurrent()
        let target = try await targets.authorize(reference)
        try checkCurrent()
        try validate(target, request)
        let result = try await planner.preview(request)
        try checkCurrent()
        try validate(target, request)
        guard !result.isStraightLine, result.datum == request.datum,
              let first = result.coordinates.first, let last = result.coordinates.last,
              SearchRoutePreview.distance(first, request.origin) <= 250,
              SearchRoutePreview.distance(last, request.destination) <= 250,
              let evidence = result.provider, !evidence.identifier.isEmpty, !evidence.attribution.isEmpty,
              abs(now().timeIntervalSince(evidence.fetchedAt)) <= 30,
              result.distanceMeters > 0, (result.etaSeconds ?? 0) > 0, !result.steps.isEmpty else {
            throw WalkingNavigationFailure.noRoute
        }
        return result
    }
    public func cancel() { cancelled = true; planner.cancel() }
    private func checkCurrent() throws {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        guard current() else { throw WalkingNavigationFailure.staleContext }
    }
    private func validate(_ target: AuthorizedWalkingTarget, _ request: SearchRouteRequest) throws {
        guard target.reference == reference, target.expiresAt > now(),
              target.expiresAt.timeIntervalSince(now()) <= 300 else { throw WalkingNavigationFailure.targetUnavailable }
        guard request.mode == .walking, request.datum == .wgs84,
              target.coordinate.datum == request.datum, target.coordinate.region == request.region,
              target.coordinate.point == request.destination else { throw WalkingNavigationFailure.coordinateUnsupported }
    }
}
