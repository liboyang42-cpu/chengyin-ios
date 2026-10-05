import Foundation
import CoreMotion
import UIKit

/// Only CMPedometer on an iPhone. No HealthKit, Watch or encrypted WeRun bridge.
/// Reading a count is user-reported sensor evidence, never proof of walking.
@MainActor final class IPhonePedometerProvider: NativePedometerProviding {
    private let enabled: Bool
    private let purpose: () -> String?
    private var pedometer: CMPedometer?
    private var generation = UUID()
    private var pending: CheckedContinuation<NativePedometerReading, Error>?
    init(enabled: Bool = false, purpose: @escaping () -> String? = { Bundle.main.object(forInfoDictionaryKey: "NSMotionUsageDescription") as? String }) {
        self.enabled = enabled; self.purpose = purpose
    }
    var permission: NativePlatformPermission {
        guard enabled, UIDevice.current.userInterfaceIdiom == .phone, CMPedometer.isStepCountingAvailable() else { return .unsupported }
        switch CMPedometer.authorizationStatus() {
        case .authorized: return .allowed
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .unsupported
        }
    }
    func read(from: Date, to: Date) async throws -> NativePedometerReading {
        guard enabled else { throw NativePlatformIssue.disabled }
        guard purpose()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw NativePlatformIssue.purposeMissing }
        switch permission {
        case .denied: throw NativePlatformIssue.denied
        case .restricted: throw NativePlatformIssue.restricted
        case .unsupported: throw NativePlatformIssue.unsupported
        case .allowed, .notDetermined: break
        }
        guard pending == nil, from < to, to <= Date(), to.timeIntervalSince(from) <= 86_400 * 2 else { throw NativePlatformIssue.invalidContract }
        let attempt = generation
        let device = CMPedometer(); pedometer = device
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                // This is the only API which can trigger Motion & Fitness consent;
                // the normal host calls it only after the explicit purpose review.
                device.queryPedometerData(from: from, to: to) { [weak self] data, error in
                    Task { @MainActor in
                        guard let self, self.generation == attempt, let continuation = self.pending else { return }
                        self.pending = nil; self.pedometer = nil
                        if self.permission == .denied { continuation.resume(throwing: NativePlatformIssue.denied) }
                        else if self.permission == .restricted { continuation.resume(throwing: NativePlatformIssue.restricted) }
                        else if let error { continuation.resume(throwing: error) }
                        else if let data {
                            do {
                                guard abs(data.startDate.timeIntervalSince(from)) < 1, abs(data.endDate.timeIntervalSince(to)) < 1,
                                      data.numberOfSteps.doubleValue.isFinite, data.numberOfSteps.doubleValue <= Double(Int.max) else { throw NativePlatformIssue.invalidContract }
                                continuation.resume(returning: try NativePedometerReading(start: data.startDate, end: data.endDate, steps: data.numberOfSteps.intValue))
                            } catch { continuation.resume(throwing: error) }
                        } else { continuation.resume(throwing: NativePlatformIssue.invalidContract) }
                    }
                }
            }
        }, onCancel: { [weak self] in Task { @MainActor in self?.cancel() } })
    }
    func cancel() {
        generation = UUID(); pedometer?.stopUpdates(); pedometer?.stopEventUpdates(); pedometer = nil
        pending?.resume(throwing: NativePlatformIssue.interrupted); pending = nil
    }
}
