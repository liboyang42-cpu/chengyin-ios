#if DEBUG
import Foundation

/// Synthetic collaborators flow through the shipping factory and MKDirections adapter seam.
/// No fixture bypasses the coordinator or makes a real route/location request.
@MainActor final class WalkingNavigationFixtureSupport {
    let targets = WalkingFixtureTargets()
    let location = WalkingFixtureLocation()
    let directions = WalkingFixtureDirections()
    var context: RuntimeDependencyContext?
    lazy var factory: NativeWalkingNavigationFactory = {
        guard let owner = context else { return NativeWalkingNavigationFactory() }
        let dependencies = NativeWalkingNavigationDependencies(owner: owner, verifiedMapKitWGS84Regions: ["US"], targets: targets,
            makeLocation: { [location] in location },
            makePlanner: { [directions] regions in MapKitWalkingRoutePlanner(verifiedRegions: regions, executor: directions) })
        return NativeWalkingNavigationFactory(dependencies: dependencies, context: { [weak self] in self?.context })
    }()
    init(scenario: String = "content") {
        if let session = try? PlayExperienceSession(accountID: 71, epoch: 1, namespace: "walking.synthetic", token: "synthetic"),
           let url = URL(string: "https://walking.invalid/") {
            context = .init(market: .unitedStates, baseURL: url, role: "player", session: session)
        }
        if scenario == "permissionDenied" { location.authorization = .denied }
        if scenario == "weakGPS" { location.accuracy = 200 }
        if scenario == "noRoute" { directions.failure = .noRoute }
        if scenario == "network" { directions.failure = .network }
        if scenario == "locked" { targets.failure = .targetUnavailable }
    }
}
@MainActor final class WalkingFixtureTargets: WalkingTargetAuthorizing {
    var failure: WalkingNavigationFailure?
    func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        if let failure { throw failure }
        return try .init(reference: reference, title: "Synthetic authorized stop",
            coordinate: WalkingCoordinate(point: RoamCoordinate(latitude: 1.004, longitude: 1.006)!, datum: .wgs84, region: "US"),
            authorityRevision: "synthetic-1", expiresAt: Date().addingTimeInterval(120))
    }
}
@MainActor final class WalkingFixtureLocation: WalkingLocationProviding {
    var authorization: WalkingLocationAuthorization = .authorized
    var accuracy = 5.0
    func currentFix() async throws -> RoamDeviceFix {
        try .init(coordinate: RoamCoordinate(latitude: 1, longitude: 1)!, accuracyMeters: accuracy, measuredAt: Date(), datum: .wgs84)
    }
    func stop() {}
}
@MainActor final class WalkingFixtureDirections: MapKitWalkingDirectionsExecuting {
    var failure: WalkingNavigationFailure?
    func calculate(_ request: SearchRouteRequest) async throws -> MapKitWalkingRouteSnapshot {
        if let failure { throw failure }
        return .init(coordinates: [request.origin, RoamCoordinate(latitude: 1, longitude: 1.006)!, request.destination],
                     distanceMeters: 1_110, etaSeconds: 900,
                     steps: [.init(instruction: "Synthetic east path", distanceMeters: 666), .init(instruction: "Synthetic north path", distanceMeters: 444)],
                     advisoryNotices: [])
    }
    func cancel() {}
}
#endif
