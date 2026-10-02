import Foundation
import Observation

/// Streaming source boundary matches Flutter StillnessSampleSource.watch(). Permission
/// acquisition belongs to the accepted provider, never to the state machine or view.
@MainActor public protocol PlayMotionSampleProviding: AnyObject {
    var available: Bool { get }
    func samples(context: PlayDeviceContext) -> AsyncThrowingStream<PlayAccelerationSample, Error>
    func cancel()
}
@MainActor public final class PlayDormantMotionProvider: PlayMotionSampleProviding {
    public var available: Bool { false }
    public init() {}
    public func samples(context: PlayDeviceContext) -> AsyncThrowingStream<PlayAccelerationSample, Error> {
        AsyncThrowingStream { $0.finish(throwing: PlayExperienceError.disabled) }
    }
    public func cancel() {}
}
@MainActor public final class PlaySyntheticMotionProvider: PlayMotionSampleProviding {
    public var available: Bool { true }
    public private(set) var contexts: [PlayDeviceContext] = []
    private let values: [PlayAccelerationSample]
    public init(samples: [PlayAccelerationSample]) { values = samples }
    public func samples(context: PlayDeviceContext) -> AsyncThrowingStream<PlayAccelerationSample, Error> {
        contexts.append(context)
        return AsyncThrowingStream { continuation in values.forEach { continuation.yield($0) }; continuation.finish() }
    }
    public func cancel() {}
}
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayStillnessCoordinator {
    public private(set) var machine: PlayStillnessMachine
    public private(set) var running = false
    public private(set) var issue: PlayExperienceError?
    private let provider: any PlayMotionSampleProviding
    private let currentContext: () -> PlayDeviceContext?
    private var generation: UInt64 = 0
    public var available: Bool { provider.available }
    public init(configuration: PlayStillnessConfiguration, provider: any PlayMotionSampleProviding, currentContext: @escaping () -> PlayDeviceContext?) {
        machine = .init(configuration: configuration); self.provider = provider; self.currentContext = currentContext
    }
    public func start() async {
        guard !running, available, let context = currentContext(), machine.phase != .completed, machine.phase != .failed else { return }
        generation &+= 1; let generation = generation; machine.resume(); running = true; issue = nil
        defer { if self.generation == generation { running = false } }
        do {
            for try await sample in provider.samples(context: context) {
                guard self.generation == generation, currentContext() == context, !Task.isCancelled else { return }
                machine.ingest(sample)
                if machine.phase == .completed { provider.cancel(); return }
                if machine.phase == .failed { throw PlayExperienceError.malformed }
            }
            // A stream ending before completion is not a successful sensor challenge.
            if self.generation == generation, machine.phase != .completed { machine.fail(); issue = .unknownResult }
        } catch {
            guard self.generation == generation, currentContext() == context else { return }
            machine.fail(); issue = error as? PlayExperienceError ?? .unknownResult
        }
    }
    public func pause() { generation &+= 1; provider.cancel(); running = false; machine.pause() }
}
