import Foundation

/// Preserves native camera/library presentation while fencing every invocation to the
/// captured account/role/epoch. Location takes the audited source conversion path.
@MainActor final class RuntimePlayDeviceProvider: PlayKitFramedPhotoProviding, PlayKitPhotoLibraryProviding, PlayDevicePermissionStateProviding {
    private let native: PlayNativeDeviceProvider
    private let location: any RoamDeviceLocationProviding
    private let grants: Set<PlayDeviceKind>
    private let isCurrent: () -> Bool
    init(native: PlayNativeDeviceProvider, location: any RoamDeviceLocationProviding,
         grants: Set<PlayDeviceKind>, isCurrent: @escaping () -> Bool) {
        self.native = native; self.location = location; self.grants = grants; self.isCurrent = isCurrent
    }
    var supported: Set<PlayDeviceKind> {
        guard isCurrent() else { return [] }
        var supported = native.supported.intersection(grants)
        if grants.contains(.location) { supported.insert(.location) }
        return supported
    }
    var authorizationInFlight: Bool { native.authorizationInFlight }
    func capture(_ kind: PlayDeviceKind, context: PlayDeviceContext) async throws -> PlayDeviceOutput {
        guard supported.contains(kind) else { throw PlayExperienceError.disabled }
        let result: PlayDeviceOutput
        if kind == .location {
            let fix = try RuntimeLocationProjection.gcj02(await location.currentFix())
            result = .location(fix.coordinate.longitude, fix.coordinate.latitude, coordinateSystem: "GCJ02")
        } else { result = try await native.capture(kind, context: context) }
        guard isCurrent(), !Task.isCancelled else { throw PlayExperienceError.staleSession }; return result
    }
    func capturePhoto(frame: PlayKitPhotoFrame, context: PlayDeviceContext) async throws -> PlayDeviceOutput {
        guard supported.contains(.photo) else { throw PlayExperienceError.disabled }
        let result = try await native.capturePhoto(frame: frame, context: context)
        guard isCurrent(), !Task.isCancelled else { throw PlayExperienceError.staleSession }; return result
    }
    func captureLibraryPhoto(context: PlayDeviceContext) async throws -> PlayDeviceOutput {
        guard supported.contains(.photo) else { throw PlayExperienceError.disabled }
        let result = try await native.captureLibraryPhoto(context: context)
        guard isCurrent(), !Task.isCancelled else { throw PlayExperienceError.staleSession }; return result
    }
    func cancel() { native.cancel(); location.stop() }
}

/// Reuses the accepted acceleration adapter and its m/s² conversion. The source
/// SensorsPlusStillnessSampleSource also streams acceleration in m/s² at game rate.
@MainActor final class RuntimeMotionSampleProvider: PlayMotionSampleProviding {
    private let provider: any PlayKitSensorProviding
    private let isCurrent: () -> Bool
    private var task: Task<Void, Never>?
    private var generation = UUID()
    init(provider: any PlayKitSensorProviding, isCurrent: @escaping () -> Bool) { self.provider = provider; self.isCurrent = isCurrent }
    var available: Bool { isCurrent() && provider.supported.contains(.acceleration) }
    func samples(context: PlayDeviceContext) -> AsyncThrowingStream<PlayAccelerationSample, Error> {
        cancel()
        let generation = self.generation
        return AsyncThrowingStream { continuation in
            guard available else { continuation.finish(throwing: PlayExperienceError.disabled); return }
            task = Task { [weak self] in
                guard let self else { continuation.finish(throwing: CancellationError()); return }
                do {
                    guard self.available, self.generation == generation, !Task.isCancelled else { throw PlayExperienceError.staleSession }
                    if let authorizing = self.provider as? any PlayKitSensorAuthorizing { try await authorizing.prepare(.acceleration) }
                    guard self.isCurrent(), !Task.isCancelled else { throw PlayExperienceError.staleSession }
                    for try await value in self.provider.samples(.acceleration) {
                        guard self.isCurrent(), !Task.isCancelled else { throw PlayExperienceError.staleSession }
                        if case .acceleration(let x, let y, let z, let timestamp) = value {
                            continuation.yield(.init(x: x, y: y, z: z, timestamp: timestamp))
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
                if self.generation == generation { self.provider.cancel() }
            }
            continuation.onTermination = { [weak self] _ in Task { @MainActor in
                guard self?.generation == generation else { return }; self?.cancel()
            } }
        }
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; provider.cancel() }
}
