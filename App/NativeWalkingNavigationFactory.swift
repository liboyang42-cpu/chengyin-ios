import Foundation
import SwiftUI

/// Exact approved context and device-tested coordinate/coverage regions are composition data,
/// not remote toggles. Empty defaults cannot create a network/location-capable coordinator.
@MainActor struct NativeWalkingNavigationDependencies {
    let owner: RuntimeDependencyContext
    let verifiedMapKitWGS84Regions: Set<String>
    let targets: any WalkingTargetAuthorizing
    var makeLocation: @MainActor () -> any WalkingLocationProviding = { WalkingForegroundLocationProvider(enabled: true) }
    var makePlanner: (@MainActor (Set<String>) -> any SearchRoutePlanning)? = nil
}

@MainActor final class NativeWalkingNavigationFactory {
    private let dependencies: NativeWalkingNavigationDependencies?
    private let context: () -> RuntimeDependencyContext?
    init(dependencies: NativeWalkingNavigationDependencies? = nil, context: @escaping () -> RuntimeDependencyContext? = { nil }) {
        self.dependencies = dependencies; self.context = context
    }
    var available: Bool {
        guard let dependencies, context() == dependencies.owner else { return false }
        return !dependencies.verifiedMapKitWGS84Regions.isEmpty
    }
    func make(reference: WalkingTargetReference) -> WalkingNavigationCoordinator? {
        guard reference.isValid, available, let dependencies else { return nil }
        let owner = dependencies.owner
        let planner = dependencies.makePlanner?(dependencies.verifiedMapKitWGS84Regions)
            ?? MapKitWalkingRoutePlanner(verifiedRegions: dependencies.verifiedMapKitWGS84Regions)
        return WalkingNavigationCoordinator(reference: reference, ownerNamespace: namespace(owner),
            authorizer: RegionBoundWalkingTargets(base: dependencies.targets, regions: dependencies.verifiedMapKitWGS84Regions),
            location: dependencies.makeLocation(), planner: planner,
            current: { [weak self] in self?.available == true && self?.context() == owner })
    }
    func restore(_ checkpoint: WalkingNavigationCheckpoint) -> WalkingNavigationCoordinator? {
        guard let dependencies, checkpoint.ownerNamespace == namespace(dependencies.owner) else { return nil }
        // Coordinates are not persisted. Caller must explicitly resume, reauthorizing the target.
        return make(reference: checkpoint.reference)
    }
    private func namespace(_ context: RuntimeDependencyContext) -> String {
        // Epoch intentionally included: a stale credential/account snapshot cannot resume.
        "\(context.baseURL.absoluteString):\(context.session.namespace):\(context.session.accountID):\(context.session.epoch):\(context.market.rawValue):\(context.role)"
    }
}
@MainActor private struct RegionBoundWalkingTargets: WalkingTargetAuthorizing {
    let base: any WalkingTargetAuthorizing
    let regions: Set<String>
    func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        let value = try await base.authorize(reference)
        guard regions.contains(value.coordinate.region), value.coordinate.datum == .wgs84 else {
            throw WalkingNavigationFailure.coordinateUnsupported
        }
        return value
    }
}
private struct WalkingNavigationFactoryKey: EnvironmentKey {
    static let defaultValue: NativeWalkingNavigationFactory? = nil
}
extension EnvironmentValues {
    var walkingNavigationFactory: NativeWalkingNavigationFactory? {
        get { self[WalkingNavigationFactoryKey.self] }
        set { self[WalkingNavigationFactoryKey.self] = newValue }
    }
}
