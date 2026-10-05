#if DEBUG
import Foundation
import SwiftUI

/// Synthetic collaborators flow through the shipping factory and MKDirections adapter seam.
/// No fixture bypasses the coordinator or makes a real route/location request.
@MainActor final class WalkingNavigationFixtureSupport {
    let targets = WalkingFixtureTargets()
    let location = WalkingFixtureLocation()
    let directions = WalkingFixtureDirections()
    var context: RuntimeDependencyContext?
    private let scenario: String
    lazy var factory: NativeWalkingNavigationFactory = {
        guard let owner = context else { return NativeWalkingNavigationFactory() }
        let dependencies = NativeWalkingNavigationDependencies(owner: owner, verifiedMapKitWGS84Regions: ["US"], targets: targets,
            makeLocation: { [location] in location },
            makePlanner: { [directions] regions in MapKitWalkingRoutePlanner(verifiedRegions: regions, executor: directions) })
        return NativeWalkingNavigationFactory(dependencies: dependencies, context: { [weak self] in self?.context })
    }()
    var scopeExpiryAction: (@MainActor () -> Void)? {
        guard scenario == "expiredScope" else { return nil }
        return { [weak self] in self?.context = nil }
    }
    init(scenario: String = "content") {
        self.scenario = scenario
        if let session = try? PlayExperienceSession(accountID: 71, epoch: 1, namespace: "walking.synthetic", token: "synthetic"),
           let url = URL(string: "https://walking.invalid/") {
            context = .init(market: .unitedStates, baseURL: url, role: "player", session: session)
        }
        if scenario == "routing" { directions.suspendNextCalculation = true }
        if scenario == "longText" { targets.title = ReferenceMapCardFixtureView.longTitle }
        if scenario == "nearDestination" { location.nearDestination = true }
        if scenario == "permissionDenied" { location.authorization = .denied }
        if scenario == "weakGPS" { location.accuracy = 200 }
        if scenario == "noRoute" { directions.failure = .noRoute }
        if scenario == "network" { directions.failure = .network }
        if scenario == "locked" { targets.failure = .targetUnavailable }
    }
}
@MainActor final class WalkingFixtureTargets: WalkingTargetAuthorizing {
    var failure: WalkingNavigationFailure?
    var title = "Synthetic authorized stop"
    func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        if let failure { throw failure }
        return try .init(reference: reference, title: title,
            coordinate: WalkingCoordinate(point: RoamCoordinate(latitude: 1.004, longitude: 1.006)!, datum: .wgs84, region: "US"),
            authorityRevision: "synthetic-1", expiresAt: Date().addingTimeInterval(120))
    }
}
@MainActor final class WalkingFixtureLocation: WalkingLocationProviding {
    var authorization: WalkingLocationAuthorization = .authorized
    var accuracy = 5.0
    var nearDestination = false
    private var fixCount = 0
    func currentFix() async throws -> RoamDeviceFix {
        fixCount += 1
        let atDestination = nearDestination && fixCount > 1
        return try .init(coordinate: RoamCoordinate(latitude: atDestination ? 1.00399 : 1, longitude: atDestination ? 1.00599 : 1)!, accuracyMeters: accuracy, measuredAt: Date(), datum: .wgs84)
    }
    func stop() {}
}
@MainActor final class WalkingFixtureDirections: MapKitWalkingDirectionsExecuting {
    var failure: WalkingNavigationFailure?
    var suspendNextCalculation = false
    private var pendingCalculation: CheckedContinuation<Void, Error>?
    var hasPendingCalculation: Bool { pendingCalculation != nil }
    func calculate(_ request: SearchRouteRequest) async throws -> MapKitWalkingRouteSnapshot {
        if suspendNextCalculation {
            suspendNextCalculation = false
            try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                    else { pendingCalculation = continuation }
                }
            }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
        }
        if let failure { throw failure }
        return .init(coordinates: [request.origin, RoamCoordinate(latitude: 1, longitude: 1.006)!, request.destination],
                     distanceMeters: 1_110, etaSeconds: 900,
                     steps: [.init(instruction: "Synthetic east path", distanceMeters: 666), .init(instruction: "Synthetic north path", distanceMeters: 444)],
                     advisoryNotices: [])
    }
    func cancel() {
        let pending = pendingCalculation; pendingCalculation = nil
        pending?.resume(throwing: CancellationError())
    }
}
/// A nil-default DEBUG-only test control; no production composition or live grant.
private struct WalkingFixtureScopeExpiryKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}
extension EnvironmentValues {
    var walkingFixtureScopeExpiry: (@MainActor () -> Void)? {
        get { self[WalkingFixtureScopeExpiryKey.self] }
        set { self[WalkingFixtureScopeExpiryKey.self] = newValue }
    }
}
#endif
