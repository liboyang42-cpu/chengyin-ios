import Foundation
import CoreLocation
import UIKit

/// No manager, permission request, or location access until the explicit action.
@MainActor final class RuntimeNativeLocationProvider: NSObject, RoamDeviceLocationProviding, CLLocationManagerDelegate {
    private let enabled: Bool
    private var manager: CLLocationManager?
    private var pending: CheckedContinuation<RoamDeviceFix, Error>?
    private var pendingID: UUID?
    private var timeout: Task<Void, Never>?
    init(enabled: Bool = false) { self.enabled = enabled; super.init() }
    func currentFix() async throws -> RoamDeviceFix {
        guard enabled, UIApplication.shared.applicationState == .active,
              CLLocationManager.locationServicesEnabled(), pending == nil,
              let purpose = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String,
              !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PlayExperienceError.disabled }
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation; pendingID = id
                let manager = CLLocationManager(); self.manager = manager
                manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)); if self?.pendingID == id { self?.finish(.failure(PlayExperienceError.unsupported)) } } catch {}
                }
                if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
                else { request(manager) }
            }
        }, onCancel: { Task { @MainActor [weak self] in if self?.pendingID == id { self?.stop() } } })
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { request(manager) }
    private func request(_ manager: CLLocationManager) {
        guard self.manager === manager, pending != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: finish(.failure(PlayExperienceError.disabled))
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard self.manager === manager else { return }
        guard let location = locations.last, let coordinate = RoamCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
              let fix = try? RoamDeviceFix(coordinate: coordinate, accuracyMeters: location.horizontalAccuracy, measuredAt: location.timestamp, datum: .wgs84) else {
            finish(.failure(PlayExperienceError.invalidAction)); return
        }
        finish(.success(fix))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard self.manager === manager else { return }; finish(.failure(error))
    }
    private func finish(_ result: Result<RoamDeviceFix, Error>) {
        let reply = pending; pending = nil; pendingID = nil; timeout?.cancel(); timeout = nil
        manager?.stopUpdatingLocation(); manager?.delegate = nil; manager = nil
        reply?.resume(with: result)
    }
    func stop() { finish(.failure(CancellationError())) }
}
