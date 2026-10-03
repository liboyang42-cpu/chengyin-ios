import Foundation
import Observation

/// No arrival, reward, completion or route-order mutation dependencies exist in this object.
@MainActor @Observable public final class WalkingNavigationCoordinator {
    public enum Phase: Equatable {
        case ready, authorizing, locating, routing, navigating, nearDestination, paused, cancelled
        case failed(WalkingNavigationFailure)
    }
    public private(set) var phase: Phase = .ready
    public private(set) var target: AuthorizedWalkingTarget?
    public private(set) var route: SearchRoutePreview?
    public private(set) var progress: WalkingNavigationProgress?
    public private(set) var accuracyMeters: Double?
    public private(set) var foreground = true
    public private(set) var replanCount = 0
    public let reference: WalkingTargetReference
    public let ownerNamespace: String
    private let authorizer: any WalkingTargetAuthorizing
    private let location: any WalkingLocationProviding
    private let planner: any SearchRoutePlanning
    private let current: () -> Bool
    private let now: () -> Date
    private var generation = UUID()
    private var busy = false
    private var lastReplanAt: Date?
    private var offRouteSamples = 0
    public init(reference: WalkingTargetReference, ownerNamespace: String,
                authorizer: any WalkingTargetAuthorizing, location: any WalkingLocationProviding,
                planner: any SearchRoutePlanning, current: @escaping () -> Bool,
                now: @escaping () -> Date = Date.init) {
        self.reference = reference; self.ownerNamespace = ownerNamespace; self.authorizer = authorizer
        self.location = location; self.planner = planner; self.current = current; self.now = now
    }
    public var canUpdate: Bool {
        route != nil && target != nil && (phase == .navigating || phase == .nearDestination || phase == .failed(.weakGPS))
    }
    public var checkpoint: WalkingNavigationCheckpoint? {
        guard current(), phase != .cancelled else { return nil }
        return .init(reference: reference, ownerNamespace: ownerNamespace)
    }
    public func start() async {
        guard !busy, foreground else { return }
        guard current() else { invalidate(); return }
        let ticket = generation
        busy = true; route = nil; progress = nil; target = nil; accuracyMeters = nil
        defer { if ticket == generation { busy = false } }
        do {
            phase = .authorizing
            let value = try await authorizer.authorize(reference)
            guard accepts(ticket) else { return }
            try validate(value)
            target = value
            let fix = try await freshFix(ticket)
            guard accepts(ticket) else { return }
            phase = .routing
            let result = try await planner.preview(request(fix: fix, target: value))
            guard accepts(ticket) else { return }
            try validate(value)
            // Directions can outlive the fix or its permission. Recheck on the main actor
            // after the await and before publishing any route, progress or arrival hint.
            // A stale request fix requires an explicit fresh-fix/new-route retry.
            try validateFix(fix)
            try validate(result, fix: fix, target: value)
            route = result; offRouteSamples = 0
            apply(fix)
        } catch { fail(error, ticket: ticket) }
    }
    /// Called only while the view is active. It stores only the latest accuracy/progress, no track.
    public func update() async {
        guard !busy, foreground, canUpdate else { return }
        guard current() else { invalidate(); return }
        let ticket = generation
        busy = true
        defer { if ticket == generation { busy = false } }
        do {
            guard let target, let route else { throw WalkingNavigationFailure.noRoute }
            try validate(target)
            let fix = try await freshFix(ticket)
            guard accepts(ticket) else { return }
            try validate(target)
            let estimate = WalkingNavigationProgress.estimate(route: route, fix: fix, destination: target.coordinate.point)
            guard let estimate else { throw WalkingNavigationFailure.noRoute }
            if estimate.distanceFromRouteMeters > max(50, fix.accuracyMeters * 2) {
                offRouteSamples += 1
                if offRouteSamples >= 3 {
                    guard replanCount < 2 else { throw WalkingNavigationFailure.replanLimit }
                    if let lastReplanAt, now().timeIntervalSince(lastReplanAt) < 30 {
                        phase = .failed(.throttled); progress = nil; return
                    }
                    replanCount += 1; lastReplanAt = now(); busy = false
                    await start(); return
                }
                // Do not display an arrival or confident progress while off the route.
                phase = .navigating; progress = nil
            } else { offRouteSamples = 0; apply(fix) }
        } catch { fail(error, ticket: ticket) }
    }
    public func pause() {
        stopWork(); route = nil; progress = nil; accuracyMeters = nil; phase = .paused
    }
    public func setForeground(_ value: Bool) {
        foreground = value
        if !value { pause() }
    }
    public func cancel() {
        stopWork(); route = nil; target = nil; progress = nil; accuracyMeters = nil; phase = .cancelled
    }
    public func synchronize() { if !current() { invalidate() } }
    private func invalidate() {
        stopWork(); target = nil; route = nil; progress = nil; accuracyMeters = nil; phase = .failed(.staleContext)
    }
    private func stopWork() { generation = UUID(); busy = false; planner.cancel(); location.stop() }
    private func accepts(_ ticket: UUID) -> Bool {
        guard ticket == generation else { return false }
        guard current() else { invalidate(); return false }
        if Task.isCancelled { cancel(); return false }
        return foreground
    }
    private func freshFix(_ ticket: UUID) async throws -> RoamDeviceFix {
        switch location.authorization {
        case .notDetermined: throw WalkingNavigationFailure.permissionRequired
        case .denied: throw WalkingNavigationFailure.permissionDenied
        case .authorized: break
        }
        phase = .locating
        let fix = try await location.currentFix()
        guard accepts(ticket) else { throw CancellationError() }
        accuracyMeters = fix.accuracyMeters
        try validateFix(fix)
        return fix
    }
    private func validateFix(_ fix: RoamDeviceFix) throws {
        guard location.authorization == .authorized else { throw WalkingNavigationFailure.permissionDenied }
        guard fix.datum == .wgs84 else { throw WalkingNavigationFailure.coordinateUnsupported }
        let age = now().timeIntervalSince(fix.measuredAt)
        guard age.isFinite, age >= -5, age <= 15, fix.accuracyMeters <= 40 else { throw WalkingNavigationFailure.weakGPS }
    }
    private func request(fix: RoamDeviceFix, target: AuthorizedWalkingTarget) -> SearchRouteRequest {
        .init(origin: fix.coordinate, destination: target.coordinate.point, mode: .walking,
              datum: target.coordinate.datum, region: target.coordinate.region)
    }
    private func validate(_ value: AuthorizedWalkingTarget) throws {
        guard value.reference == reference, value.expiresAt > now(), value.expiresAt.timeIntervalSince(now()) <= 300 else {
            throw WalkingNavigationFailure.targetUnavailable
        }
        // The first adapter accepts only explicitly supplied WGS84. Never reverse/project a
        // backend GCJ02 target using RuntimeLocationProjection or the user's language/market.
        guard value.coordinate.datum == .wgs84 else { throw WalkingNavigationFailure.coordinateUnsupported }
    }
    private func validate(_ result: SearchRoutePreview, fix: RoamDeviceFix, target: AuthorizedWalkingTarget) throws {
        guard !result.isStraightLine, result.datum == .wgs84, let evidence = result.provider,
              !evidence.identifier.isEmpty, !evidence.attribution.isEmpty,
              abs(now().timeIntervalSince(evidence.fetchedAt)) <= 30,
              result.coordinates.count <= 100_000, result.distanceMeters > 0,
              result.etaSeconds != nil, !result.steps.isEmpty,
              result.steps.allSatisfy({ !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              let first = result.coordinates.first, let last = result.coordinates.last,
              SearchRoutePreview.distance(first, fix.coordinate) <= 250,
              SearchRoutePreview.distance(last, target.coordinate.point) <= 250,
              WalkingNavigationProgress.estimate(route: result, fix: fix, destination: target.coordinate.point) != nil
        else { throw WalkingNavigationFailure.noRoute }
    }
    private func apply(_ fix: RoamDeviceFix) {
        guard let route, let target else { return }
        progress = WalkingNavigationProgress.estimate(route: route, fix: fix, destination: target.coordinate.point)
        phase = progress?.nearDestination == true ? .nearDestination : .navigating
    }
    private func fail(_ error: Error, ticket: UUID) {
        guard accepts(ticket) else { return }
        if error is CancellationError { phase = .cancelled; route = nil; progress = nil; return }
        let failure = error as? WalkingNavigationFailure ?? (error is WalkingTargetReadFailure ? .targetUnavailable : .network)
        phase = .failed(failure); progress = nil
        if failure != .weakGPS { route = nil }
        if failure == .targetUnavailable || failure == .coordinateUnsupported || failure == .staleContext { target = nil }
    }
}
