import Foundation
import CoreLocation
import UIKit

/// This feature cannot request or expand permissions. It uses an already-authorized
/// foreground fix only, and never enables background location, presence or track recording.
@MainActor final class WalkingForegroundLocationProvider: NSObject, WalkingLocationProviding, CLLocationManagerDelegate {
    private let enabled: Bool
    private var manager: CLLocationManager?
    private var pending: CheckedContinuation<RoamDeviceFix, Error>?
    private var pendingID: UUID?
    private var timeout: Task<Void, Never>?
    init(enabled: Bool = false) { self.enabled = enabled; super.init() }
    var authorization: WalkingLocationAuthorization {
        guard enabled else { return .notDetermined }
        // Querying status does not prompt. No manager exists until an explicit foreground action.
        guard CLLocationManager.locationServicesEnabled() else { return .denied }
        switch manager?.authorizationStatus ?? CLLocationManager.authorizationStatus() {
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }
    func currentFix() async throws -> RoamDeviceFix {
        guard enabled, UIApplication.shared.applicationState == .active else { throw WalkingNavigationFailure.unavailable }
        guard authorization == .authorized else {
            throw authorization == .denied ? WalkingNavigationFailure.permissionDenied : WalkingNavigationFailure.permissionRequired
        }
        guard pending == nil else { throw WalkingNavigationFailure.throttled }
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { reply in
                pending = reply; pendingID = id
                let manager = CLLocationManager(); self.manager = manager
                manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest
                manager.activityType = .fitness
                timeout = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(15))
                        if self?.pendingID == id { self?.finish(.failure(WalkingNavigationFailure.weakGPS)) }
                    } catch {}
                }
                manager.requestLocation()
            }
        }, onCancel: { Task { @MainActor [weak self] in if self?.pendingID == id { self?.stop() } } })
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard self.manager === manager, pending != nil else { return }
        if authorization != .authorized { finish(.failure(WalkingNavigationFailure.permissionDenied)) }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard self.manager === manager else { return }
        guard UIApplication.shared.applicationState == .active, authorization == .authorized else {
            finish(.failure(WalkingNavigationFailure.permissionDenied)); return
        }
        guard let value = locations.last,
              let point = RoamCoordinate(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude),
              let fix = try? RoamDeviceFix(coordinate: point, accuracyMeters: value.horizontalAccuracy,
                                           measuredAt: value.timestamp, datum: .wgs84) else {
            finish(.failure(WalkingNavigationFailure.weakGPS)); return
        }
        finish(.success(fix))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard self.manager === manager else { return }
        finish(.failure((error as? CLError)?.code == .denied ? WalkingNavigationFailure.permissionDenied : WalkingNavigationFailure.weakGPS))
    }
    private func finish(_ result: Result<RoamDeviceFix, Error>) {
        let reply = pending; pending = nil; pendingID = nil; timeout?.cancel(); timeout = nil
        manager?.stopUpdatingLocation(); manager?.delegate = nil; manager = nil
        reply?.resume(with: result)
    }
    func stop() { finish(.failure(CancellationError())) }
}
