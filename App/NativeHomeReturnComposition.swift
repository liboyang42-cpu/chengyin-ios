import Foundation
import CoreLocation
import UIKit

/// Reuses the existing already-authorized foreground provider. No automatic permission or background sampling.
@MainActor final class NativeHomeReturnForegroundLocation {
    private let provider: any WalkingLocationProviding
    private let servicesEnabled: () -> Bool
    private let isForeground: () -> Bool
    private var activeSample: UUID?
    convenience init() {
        self.init(provider: WalkingForegroundLocationProvider(enabled: true),
            servicesEnabled: { CLLocationManager.locationServicesEnabled() },
            isForeground: { UIApplication.shared.applicationState == .active })
    }
    /// The seam has no authorization-request operation. Tests inject no OS manager or permission.
    init(provider: any WalkingLocationProviding, servicesEnabled: @escaping () -> Bool,
         isForeground: @escaping () -> Bool) {
        self.provider = provider; self.servicesEnabled = servicesEnabled; self.isForeground = isForeground
    }
    var isAuthorized: Bool { authorizationFailure == nil && isForeground() }
    private var authorizationFailure: NativeHomeReturnLocationStatus? {
        guard servicesEnabled() else { return .servicesOff }
        switch provider.authorization {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return nil
        }
    }
    // Existing preflight rejects negative accuracy before constructing a check. This carries
    // no coordinates and cannot become evidence; it is not an empty or synthetic location.
    private var unavailable: NativeHomeReturnLocationStatus { .fix(accuracyMeters: -1, capturedAt: Date()) }
    func sample() async -> NativeHomeReturnLocationStatus {
        if let failure = authorizationFailure { return failure }
        guard isForeground(), !Task.isCancelled, activeSample == nil else { return unavailable }
        let ticket = UUID(); activeSample = ticket
        defer { if activeSample == ticket { activeSample = nil } }
        do {
            let value = try await provider.currentFix()
            // Authorization/lifecycle may change between the delegate callback and resumption.
            // A stopped or cancelled attempt must not publish the callback's old coordinate.
            guard activeSample == ticket, !Task.isCancelled else { return unavailable }
            if let failure = authorizationFailure { return failure }
            guard isForeground(), value.datum == .wgs84 else { return unavailable }
            return .measured(try NativeHomeReturnFix(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude,
                accuracyMeters: value.accuracyMeters, capturedAt: value.measuredAt))
        } catch {
            guard activeSample == ticket, !Task.isCancelled else { return unavailable }
            if let failure = authorizationFailure { return failure }
            guard isForeground() else { return unavailable }
            switch error as? WalkingNavigationFailure {
            case .permissionDenied: return .denied
            case .permissionRequired: return .notDetermined
            default: return unavailable
            }
        }
    }
    func stop() {
        activeSample = nil
        provider.stop()
    }
}

extension AppCompositionRoot {
    func makeNativeHomeReturnSelection(context: RuntimeDependencyContext, approval: NativeHomeReturnApproval,
                current: @escaping () -> RuntimeDependencyContext?,
                selected: @escaping (RuntimeDependencyContext) -> NativeHomeReturnApproval?) -> NativeHomeReturnSelectionCoordinator? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration, let homeGrant = reviewed.privateHome,
              homeGrant.matches(storageScope: reviewed.storageScope, accountID: context.session.accountID, role: context.role),
              reviewed.regional.market == context.market, api.baseURL == context.baseURL,
              reviewed.storageScope.service == context.session.namespace,
              context.role.utf8.elementsEqual(context.session.role.utf8), approval.matches(context),
              let primitive = storage.privateHomeKeychain,
              let journal = try? NativeHomeReturnKeychainJournal(storageScope: reviewed.storageScope, owner: context.session, primitive: primitive),
              current() == context, selected(context)?.revision == approval.revision else { return nil }
        guard let transport = makeNativeHomeReturnTransport(approval: approval, current: current, selected: selected) else { return nil }
        let service = NativeHomeReturnService(approval: approval, transport: transport, current: current, selected: selected)
        let location = NativeHomeReturnForegroundLocation()
        return NativeHomeReturnSelectionCoordinator(service: service, journal: journal, owner: context.session,
            isCurrent: { service.isCurrent() }, makeModel: { scope in
                NativeHomeReturnCoordinator(scope: scope, service: service, journal: journal, owner: context.session,
                    enabled: true, location: { await location.sample() }, stopLocation: { location.stop() }, locationAuthorized: { location.isAuthorized },
                    isCurrent: { service.isCurrent() })
            })
    }
}
