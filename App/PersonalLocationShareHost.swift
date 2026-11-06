import SwiftUI
import Network
import CoreLocation
import UIKit

/// Normal root injection. Endpoint and collection-purpose approvals are independent and all default to nil.
@MainActor final class PersonalLocationShareHost: ObservableObject {
    private let baseURL: () -> URL?
    private let currentScope: () -> PersonalLocationShareScope?
    private let token: () -> String?
    private let readApproval: () -> PersonalLocationShareEndpointApproval?
    private let writeApproval: () -> PersonalLocationShareEndpointApproval?
    private let captureApproval: () -> PersonalLocationShareCaptureApproval?
    private let journal: any PersonalLocationShareJournaling
    private let monitor = NWPathMonitor()
    private var foreground = false
    private var connected = false
    private var retained: PersonalLocationShareCoordinator?
    private(set) var retainedServiceLease: UUID?
    private var authorizationBlockedScope: PersonalLocationShareScope?
    @Published private(set) var revision: UInt64 = 0
    init(baseURL: @escaping () -> URL?, currentScope: @escaping () -> PersonalLocationShareScope?,
         token: @escaping () -> String?, journal: any PersonalLocationShareJournaling,
         readApproval: @escaping () -> PersonalLocationShareEndpointApproval? = { nil },
         writeApproval: @escaping () -> PersonalLocationShareEndpointApproval? = { nil },
         captureApproval: @escaping () -> PersonalLocationShareCaptureApproval? = { nil }) {
        self.baseURL = baseURL; self.currentScope = currentScope; self.token = token; self.journal = journal
        self.readApproval = readApproval; self.writeApproval = writeApproval; self.captureApproval = captureApproval
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in self?.connectionChanged(connected) }
        }
        monitor.start(queue: DispatchQueue(label: "personal-location-share-path"))
    }
    deinit { monitor.cancel() }
    func coordinator() -> PersonalLocationShareCoordinator? {
        guard let scope = currentScope(), authorizationBlockedScope != scope, let url = baseURL() else { return nil }
        if let retained, retained.scope == scope { return retained }
        retained?.suspend(foreground: false, connected: connected)
        let serviceLease = UUID()
        let service = PersonalLocationShareHTTPService(baseURL: url, scope: scope,
            transport: PersonalLocationShareURLTransport(), current: currentScope, token: token,
            readApproval: readApproval, writeApproval: writeApproval,
            isCurrentService: { [weak self] in self?.retainedServiceLease == serviceLease },
            authorizationGeneration: { [weak self] in self?.retained?.authorizationGeneration ?? UInt64.max },
            onAuthorizationFailure: { [weak self] error in self?.authorizationRejected(scope: scope, serviceLease: serviceLease, error: error) })
        let factory = PersonalLocationShareCoreLocationFactory(permitted: { [weak self] scope in
            guard let self, self.retainedServiceLease == serviceLease, self.currentScope() == scope, let url = self.baseURL(),
                  self.captureApproval()?.permits(scope: scope, installedUsageDescription:
                    Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String) == true else { return false }
            return [PersonalLocationShareOperation.context, .requestStatus].allSatisfy { self.readApproval()?.permits($0, baseURL: url) == true } &&
                [PersonalLocationShareOperation.create, .publish, .revoke].allSatisfy { self.writeApproval()?.permits($0, baseURL: url) == true }
        }, captureApproval: captureApproval, foreground: { [weak self] in
            self?.foreground == true && self?.connected == true && UIApplication.shared.applicationState == .active
        })
        let coordinator = PersonalLocationShareCoordinator(scope: scope, service: service, journal: journal,
            providerFactory: factory, current: currentScope)
        coordinator.resume(foreground: foreground, connected: connected)
        retainedServiceLease = serviceLease; retained = coordinator; return coordinator
    }
    func authorizationRejected(scope: PersonalLocationShareScope, serviceLease: UUID, error: PersonalLocationShareFailure) {
        guard currentScope() == scope, retained?.scope == scope, retainedServiceLease == serviceLease else { return }
        retained?.authorizationRejected(error)
        retained = nil; retainedServiceLease = nil; authorizationBlockedScope = scope; revision &+= 1
    }
    func sessionWillChange() {
        authorizationBlockedScope = nil
        retained?.suspend(foreground: false, connected: false)
        retained = nil; retainedServiceLease = nil; revision &+= 1
    }
    func prepareLogout() {
        // Synchronous local shutdown and durable stop intent must never await a remote revoke.
        // Session invalidation on the server is the fallback when the old credential retires first.
        retained?.suspend(foreground: false, connected: connected)
        retained = nil; retainedServiceLease = nil; revision &+= 1
    }
    func sceneChanged(_ phase: ScenePhase) {
        foreground = phase == .active
        if foreground { retained?.resume(foreground: true, connected: connected) }
        else { retained?.suspend(foreground: false, connected: connected) }
    }
    private func connectionChanged(_ value: Bool) {
        connected = value
        if value { retained?.resume(foreground: foreground, connected: true) }
        else { retained?.suspend(foreground: foreground, connected: false) }
    }
}
// Real CoreLocation driver. No map/roaming consent, cached fix, distance filter or measurement claim.
@MainActor protocol PersonalLocationShareLocationDriver: AnyObject {
    var authorization: CLAuthorizationStatus { get }
    var accuracy: CLAccuracyAuthorization { get }
    var onLocation: ((CLLocation) -> Void)? { get set }
    var onAuthorization: (() -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
    func requestForegroundAuthorization()
    func start()
    func stop()
}
@MainActor final class PersonalLocationShareCoreLocationDriver: NSObject, PersonalLocationShareLocationDriver, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: ((CLLocation) -> Void)?
    var onAuthorization: (() -> Void)?
    var onFailure: ((Error) -> Void)?
    var authorization: CLAuthorizationStatus { manager.authorizationStatus }
    var accuracy: CLAccuracyAuthorization { manager.accuracyAuthorization }
    override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = false
        // No app-defined desiredAccuracy/distanceFilter: the wire approves output precision, not a sensor accuracy in metres.
    }
    func requestForegroundAuthorization() { manager.requestWhenInUseAuthorization() }
    func start() { manager.startUpdatingLocation() }
    func stop() {
        manager.stopUpdatingLocation(); manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false; manager.delegate = nil
        onLocation = nil; onAuthorization = nil; onFailure = nil
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard self.manager === manager else { return }; onAuthorization?()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard self.manager === manager else { return }
        if let location = locations.last { onLocation?(location) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard self.manager === manager else { return }; onFailure?(error)
    }
}

/// Each acquisition has a new manager identity and a new callback generation. No coordinates are retained.
@MainActor final class PersonalLocationShareCoreLocationProvider: PersonalLocationShareCoordinateProviding {
    let isSynthetic: Bool
    private let requiresFullAccuracy: Bool
    private let allowsFirstPermissionRequest: Bool
    private let permitted: () -> Bool
    private let foreground: () -> Bool
    private let servicesEnabled: () -> Bool
    private let makeDriver: () -> any PersonalLocationShareLocationDriver
    private var driver: (any PersonalLocationShareLocationDriver)?
    private var pending: CheckedContinuation<PersonalLocationShareSample, Error>?
    private var acquisitionId: UUID?
    private var acquisitionStartedAt: Date?
    private var requestedPermission = false
    private var stopped = false
    convenience init(binding: PersonalLocationShareCaptureBinding, isSynthetic: Bool, permitted: @escaping () -> Bool,
         foreground: @escaping () -> Bool, servicesEnabled: @escaping () -> Bool,
         makeDriver: @escaping () -> any PersonalLocationShareLocationDriver) {
        self.init(requiresFullAccuracy: binding.grant.mode == .exact,
            allowsFirstPermissionRequest: binding.allowsFirstPermissionRequest, isSynthetic: isSynthetic,
            permitted: permitted, foreground: foreground, servicesEnabled: servicesEnabled, makeDriver: makeDriver)
    }
    /// Sensor-only seam. This does not grant sharing authority; each factory must enforce its own binding.
    init(requiresFullAccuracy: Bool, allowsFirstPermissionRequest: Bool, isSynthetic: Bool,
         permitted: @escaping () -> Bool, foreground: @escaping () -> Bool,
         servicesEnabled: @escaping () -> Bool, makeDriver: @escaping () -> any PersonalLocationShareLocationDriver) {
        self.requiresFullAccuracy = requiresFullAccuracy; self.allowsFirstPermissionRequest = allowsFirstPermissionRequest
        self.isSynthetic = isSynthetic; self.permitted = permitted
        self.foreground = foreground; self.servicesEnabled = servicesEnabled; self.makeDriver = makeDriver
    }
    private var active: Bool { !stopped && permitted() && foreground() }
    func sample() async throws -> PersonalLocationShareSample {
        guard active, servicesEnabled(), pending == nil else { throw PersonalLocationShareFailure.providerUnavailable }
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { reply in
                guard active else { reply.resume(throwing: PersonalLocationShareFailure.staleSession); return }
                pending = reply; acquisitionId = id; acquisitionStartedAt = Date(); requestedPermission = false
                let source = makeDriver(); driver = source
                source.onLocation = { [weak self] location in self?.receive(location, acquisition: id) }
                source.onAuthorization = { [weak self] in self?.authorizationChanged(acquisition: id) }
                source.onFailure = { [weak self] error in self?.finish(.failure(error), acquisition: id) }
                authorizationChanged(acquisition: id)
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                guard self?.acquisitionId == id else { return }; self?.stop()
            }
        })
    }
    private func authorizationChanged(acquisition id: UUID) {
        guard acquisitionId == id, pending != nil, let driver else { return }
        guard active, servicesEnabled() else { finish(.failure(PersonalLocationShareFailure.staleSession), acquisition: id); return }
        switch driver.authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requiresFullAccuracy || driver.accuracy == .fullAccuracy else {
                finish(.failure(PersonalLocationShareFailure.reducedAccuracyUnavailable), acquisition: id); return
            }
            driver.start()
        case .notDetermined:
            // This capability originates only from the separate, explicit final-confirmation button.
            guard allowsFirstPermissionRequest else {
                finish(.failure(PersonalLocationShareFailure.existingLocationPermissionRequired), acquisition: id); return
            }
            guard !requestedPermission else { return }
            requestedPermission = true; driver.requestForegroundAuthorization()
        case .denied, .restricted:
            finish(.failure(PersonalLocationShareFailure.existingLocationPermissionRequired), acquisition: id)
        @unknown default:
            finish(.failure(PersonalLocationShareFailure.existingLocationPermissionRequired), acquisition: id)
        }
    }
    private func receive(_ value: CLLocation, acquisition id: UUID) {
        guard acquisitionId == id, pending != nil, let driver else { return }
        guard active, servicesEnabled(), [.authorizedWhenInUse, .authorizedAlways].contains(driver.authorization) else {
            finish(.failure(PersonalLocationShareFailure.staleSession), acquisition: id); return
        }
        let accuracy: PersonalLocationShareSystemAccuracy
        switch driver.accuracy {
        case .fullAccuracy: accuracy = .full
        case .reducedAccuracy: accuracy = .reduced
        @unknown default: accuracy = .unknown
        }
        guard !requiresFullAccuracy || accuracy == .full else {
            finish(.failure(PersonalLocationShareFailure.reducedAccuracyUnavailable), acquisition: id); return
        }
        // Ignore an OS-delivered cached fix rather than relabeling it as a new observation.
        guard let started = acquisitionStartedAt, value.timestamp >= started else { return }
        guard value.timestamp <= Date() else { finish(.failure(PersonalLocationShareFailure.invalidContract), acquisition: id); return }
        let milliseconds = value.timestamp.timeIntervalSince1970 * 1000
        guard CLLocationCoordinate2DIsValid(value.coordinate), value.horizontalAccuracy.isFinite,
              value.horizontalAccuracy >= 0, milliseconds.isFinite, milliseconds > 0, milliseconds < Double(Int64.max),
              value.sourceInformation?.isSimulatedBySoftware != true else {
            finish(.failure(PersonalLocationShareFailure.invalidContract), acquisition: id); return
        }
        // WGS84 comes from CoreLocation, never a map-adjusted datum. Accuracy is not a fabricated wire field.
        let sample = PersonalLocationShareSample(observedAtMs: Int64(milliseconds), datum: "WGS84",
            latitude: value.coordinate.latitude, longitude: value.coordinate.longitude,
            sourceId: "CoreLocation.foreground", systemAccuracy: accuracy)
        finish(.success(sample), acquisition: id)
    }
    private func finish(_ result: Result<PersonalLocationShareSample, Error>, acquisition id: UUID) {
        guard acquisitionId == id else { return }
        acquisitionId = nil; acquisitionStartedAt = nil; requestedPermission = false
        let reply = pending; pending = nil
        driver?.stop(); driver = nil // Synchronous stop before any continuation resumes.
        reply?.resume(with: result)
    }
    func stop() {
        stopped = true
        if let id = acquisitionId { finish(.failure(CancellationError()), acquisition: id) }
        else { driver?.stop(); driver = nil }
    }
}

/// Inert until both the normal host's three approvals and a current explicitly-confirmed grant exist.
@MainActor final class PersonalLocationShareCoreLocationFactory: PersonalLocationShareCoordinateFactory {
    var isSynthetic: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    private let permitted: (PersonalLocationShareScope) -> Bool
    private let captureApproval: () -> PersonalLocationShareCaptureApproval?
    private let foreground: () -> Bool
    init(permitted: @escaping (PersonalLocationShareScope) -> Bool, captureApproval: @escaping () -> PersonalLocationShareCaptureApproval? = { nil }, foreground: @escaping () -> Bool) {
        self.permitted = permitted; self.captureApproval = captureApproval; self.foreground = foreground
    }
    func canCreate(scope: PersonalLocationShareScope) -> Bool { permitted(scope) && confirmationPurpose(scope: scope) != nil }
    func confirmationPurpose(scope: PersonalLocationShareScope) -> PersonalLocationShareCaptureApproval? {
        guard permitted(scope), let purpose = captureApproval(), purpose.scope == scope else { return nil }; return purpose
    }
    func make(binding: PersonalLocationShareCaptureBinding, isCurrent: @escaping () -> Bool) throws -> any PersonalLocationShareCoordinateProviding {
        guard permitted(binding.scope), confirmationPurpose(scope: binding.scope) == binding.capturePurpose, foreground(), isCurrent() else { throw PersonalLocationShareFailure.capturePurposeUnavailable }
        return PersonalLocationShareCoreLocationProvider(binding: binding, isSynthetic: isSynthetic,
            permitted: { [weak self] in self?.confirmationPurpose(scope: binding.scope) == binding.capturePurpose && isCurrent() }, foreground: foreground,
            servicesEnabled: { CLLocationManager.locationServicesEnabled() },
            makeDriver: { PersonalLocationShareCoreLocationDriver() })
    }
}

private struct PersonalLocationShareHostKey: EnvironmentKey {
    static let defaultValue: PersonalLocationShareHost? = nil
}
extension EnvironmentValues {
    var personalLocationShareHost: PersonalLocationShareHost? {
        get { self[PersonalLocationShareHostKey.self] }
        set { self[PersonalLocationShareHostKey.self] = newValue }
    }
}
@MainActor struct PersonalLocationShareEntry: View {
    @Environment(\.personalLocationShareHost) private var host
    let recipientId: Int64?
    var body: some View {
        if let host { PersonalLocationShareHostedEntry(host: host, recipientId: recipientId) }
        else { PersonalLocationShareUnavailableView() }
    }
}
@MainActor private struct PersonalLocationShareHostedEntry: View {
    @ObservedObject var host: PersonalLocationShareHost
    let recipientId: Int64?
    var body: some View {
        if let coordinator = host.coordinator() {
            PersonalLocationShareView(coordinator: coordinator, recipientId: recipientId)
                .id(coordinator.scope).id(host.revision)
        } else {
            PersonalLocationShareUnavailableView()
        }
    }
}

/// A normal unavailable destination, not an activation switch or a permission prompt.
@MainActor private struct PersonalLocationShareUnavailableView: View {
    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label {
                    Text("personalLocationShare.unavailable.title", tableName: "PersonalLocationShare")
                } icon: { Image(systemName: "location.slash") }
            } description: {
                Text("personalLocationShare.unavailable.description", tableName: "PersonalLocationShare")
            }
        }
        .navigationTitle(Text("personalLocationShare.title.management", tableName: "PersonalLocationShare"))
        .accessibilityIdentifier("personalLocationShare.unavailable")
    }
}
