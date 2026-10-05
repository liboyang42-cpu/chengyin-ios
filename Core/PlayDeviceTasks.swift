import Foundation
import Observation

public struct PlayStillnessConfiguration: Equatable {
    public let durationSeconds: Int
    public let tolerance: Double
    public init(durationSeconds: Int, tolerance: Double = 0.02) throws {
        guard (1...3600).contains(durationSeconds), tolerance.isFinite, tolerance > 0, tolerance <= 10 else { throw PlayExperienceError.invalidAction }
        self.durationSeconds = durationSeconds; self.tolerance = tolerance
    }
    public init(raw: PlayWireValue) throws {
        guard let duration = raw["durationSec"].tolerantInteger else { throw PlayExperienceError.invalidAction }
        let tolerance: Double
        if raw["tolerance"] == .null { tolerance = 0.02 }
        else if let number = raw["tolerance"].double { tolerance = number }
        else if let text = raw["tolerance"].text, let number = Double(text) { tolerance = number }
        else { throw PlayExperienceError.invalidAction }
        try self.init(durationSeconds: duration, tolerance: tolerance)
    }
}
public struct PlayAccelerationSample: Equatable {
    public let x: Double, y: Double, z: Double, timestamp: TimeInterval
    public init(x: Double, y: Double, z: Double, timestamp: TimeInterval) { self.x = x; self.y = y; self.z = z; self.timestamp = timestamp }
}
/// Mirrors stillness_challenge_controller.dart: five-sample variance, 250ms maximum
/// credited gap, no background time, resets on movement, completion once only.
public struct PlayStillnessMachine: Equatable {
    public enum Phase: String { case stabilizing, holding, paused, completed, failed }
    public let configuration: PlayStillnessConfiguration
    public private(set) var phase = Phase.stabilizing
    public private(set) var stableSeconds: Double = 0
    public private(set) var stability: Double = 0
    public private(set) var resetCount = 0
    public private(set) var completionCount = 0
    private var window: [PlayAccelerationSample] = []
    private var last: TimeInterval?
    private var wasStable = false
    public init(configuration: PlayStillnessConfiguration) { self.configuration = configuration }
    public mutating func pause() {
        guard phase != .completed, phase != .failed else { return }
        phase = .paused; window = []; last = nil; wasStable = false; stability = 0
    }
    public mutating func resume() {
        guard phase == .paused else { return }; phase = .stabilizing; window = []; last = nil; wasStable = false
    }
    public mutating func fail() { guard phase != .completed else { return }; phase = .failed; window = []; last = nil; wasStable = false }
    public mutating func ingest(_ sample: PlayAccelerationSample) {
        guard phase != .paused, phase != .completed, phase != .failed else { return }
        guard [sample.x, sample.y, sample.z, sample.timestamp].allSatisfy(\.isFinite), sample.timestamp >= 0 else { fail(); return }
        // An out-of-order event cannot move the time anchor backwards and earn time twice.
        if let last, sample.timestamp <= last { return }
        let previous = last; last = sample.timestamp
        window.append(sample); if window.count > 5 { window.removeFirst() }
        guard window.count == 5 else { wasStable = false; phase = .stabilizing; return }
        let mx = window.map(\.x).reduce(0, +) / 5, my = window.map(\.y).reduce(0, +) / 5, mz = window.map(\.z).reduce(0, +) / 5
        let variance = window.reduce(0.0) { sum, item in sum + pow(item.x - mx, 2) + pow(item.y - my, 2) + pow(item.z - mz, 2) } / 5
        stability = max(0, min(1, 1 - variance / configuration.tolerance))
        guard variance <= configuration.tolerance else {
            if stableSeconds > 0 { resetCount += 1 }; stableSeconds = 0; wasStable = false; phase = .stabilizing; return
        }
        if wasStable, let previous {
            let delta = sample.timestamp - previous
            if delta >= 0 && delta <= 0.250 { stableSeconds += delta }
        }
        wasStable = true
        if stableSeconds >= Double(configuration.durationSeconds) {
            stableSeconds = Double(configuration.durationSeconds); phase = .completed; completionCount = 1
        } else { phase = .holding }
    }
    public var sourcePayload: [String: PlayWireValue]? { phase == .completed ? ["heldSec": .int(configuration.durationSeconds)] : nil }
}
public struct PlayStopwatchMachine: Equatable {
    public enum Reveal: String, CaseIterable { case delay, never, always }
    public enum Phase: String { case idle, running, done }
    public struct Verdict: Equatable { public let stars: Int; public let difference: Double; public let late: Bool }
    public let target: Double
    public let tolerance: Double
    public let reveal: Reveal
    public private(set) var phase = Phase.idle
    public private(set) var result: Verdict?
    public private(set) var rounds = 0
    public private(set) var bestDifference: Double?
    private var start: TimeInterval?
    public init(target: Double = 10, tolerance: Double = 0.05, reveal: Reveal = .delay) {
        self.target = target.isFinite ? (min(60, max(3, target)) * 100).rounded() / 100 : 10
        self.tolerance = tolerance.isFinite && tolerance > 0 ? tolerance : 0.05; self.reveal = reveal
    }
    public mutating func begin(now: TimeInterval) {
        guard now.isFinite, phase != .running else { return }; start = now; result = nil; phase = .running
    }
    public func visibleElapsed(now: TimeInterval) -> Double? {
        guard phase == .running, let start, now.isFinite else { return nil }
        let elapsed = max(0, now - start)
        switch reveal { case .always: return elapsed; case .never: return nil; case .delay: return elapsed < 1 ? elapsed : nil }
    }
    public mutating func stop(now: TimeInterval) {
        guard phase == .running, let start, now.isFinite, now >= start else { return }
        let elapsed = now - start, diff = (abs(elapsed - target) * 100).rounded() / 100, scale = tolerance / 0.05
        let stars = diff <= 0.05 * scale ? 3 : diff <= 0.20 * scale ? 2 : diff <= 0.50 * scale ? 1 : 0
        result = Verdict(stars: stars, difference: diff, late: elapsed > target); rounds += 1
        bestDifference = min(bestDifference ?? diff, diff); self.start = nil; phase = .done
    }
    /// Background/interruption voids this round, preserving prior rounds/best only.
    public mutating func interrupt() { if phase == .running { start = nil; result = nil; phase = .idle } }
}
public enum PlayDeviceKind: String, CaseIterable { case scan, location, photo, microphone, motion, steps, ar, audioPlayback }
public struct PlayDeviceContext: Equatable {
    public let namespace: String; public let accountID: Int; public let epoch: UInt64; public let scope: PlaySessionScope; public let nodeID: Int
    public init(session: PlayExperienceSession, scope: PlaySessionScope, nodeID: Int) throws {
        guard scope.isValid, nodeID > 0 else { throw APIError.invalidRequest }
        namespace = session.namespace; accountID = session.accountID; epoch = session.epoch; self.scope = scope; self.nodeID = nodeID
    }
}
public enum PlayDeviceOutput: Equatable {
    case scan(String), location(Double, Double, coordinateSystem: String), photo(Data, mimeType: String)
    case sample(PlayAccelerationSample), unavailable
}
@MainActor public protocol PlayDeviceProviding {
    var supported: Set<PlayDeviceKind> { get }
    func capture(_ kind: PlayDeviceKind, context: PlayDeviceContext) async throws -> PlayDeviceOutput
    func cancel()
}
/// Safe default. The UI can inspect availability without requesting OS permissions.
@MainActor public struct PlayDormantDeviceProvider: PlayDeviceProviding {
    public let supported: Set<PlayDeviceKind> = []
    public init() {}
    public func capture(_ kind: PlayDeviceKind, context: PlayDeviceContext) async throws -> PlayDeviceOutput { .unavailable }
    public func cancel() {}
}
@MainActor public final class PlaySyntheticDeviceProvider: PlayDeviceProviding {
    public let supported: Set<PlayDeviceKind>
    public private(set) var captured: [(PlayDeviceKind, PlayDeviceContext)] = []
    private let operation: (PlayDeviceKind, PlayDeviceContext) async throws -> PlayDeviceOutput
    public init(supported: Set<PlayDeviceKind>, operation: @escaping (PlayDeviceKind, PlayDeviceContext) async throws -> PlayDeviceOutput) { self.supported = supported; self.operation = operation }
    public func capture(_ kind: PlayDeviceKind, context: PlayDeviceContext) async throws -> PlayDeviceOutput {
        guard supported.contains(kind) else { throw PlayExperienceError.unsupported }; captured.append((kind, context)); return try await operation(kind, context)
    }
    public func cancel() {}
}
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayDeviceCaptureCoordinator {
    public private(set) var output: PlayDeviceOutput?
    public private(set) var busy = false
    public private(set) var issue: PlayExperienceError?
    public private(set) var uploadedPhoto: PlayCompletionEvidence?
    private var capturedContext: PlayDeviceContext?
    private let filter: ((Data, PlayPhotoFilter) throws -> Data)?
    private let upload: ((Data, String, PlayDeviceContext) async throws -> String)?
    private let provider: any PlayDeviceProviding
    private let current: () -> PlayDeviceContext?
    private var generation: UInt64 = 0
    public init(provider: (any PlayDeviceProviding)? = nil,
                filter: ((Data, PlayPhotoFilter) throws -> Data)? = nil,
                upload: ((Data, String, PlayDeviceContext) async throws -> String)? = nil,
                current: @escaping () -> PlayDeviceContext?) {
        self.provider = provider ?? PlayDormantDeviceProvider(); self.upload = upload; self.filter = filter; self.current = current
    }
    public var canUpload: Bool {
        guard case .photo = output else { return false }
        return upload != nil && capturedContext == current() && uploadedPhoto == nil && !busy
    }
    /// Explicit user upload step. Completion still requires the journey's separate review.
    public func uploadPhoto() async {
        guard !busy, uploadedPhoto == nil, let upload, let context = capturedContext, current() == context,
              case .photo(let bytes, let mime) = output else { issue = .disabled; return }
        generation &+= 1; let generation = generation; busy = true; issue = nil; uploadedPhoto = nil
        defer { if self.generation == generation { busy = false } }
        do {
            let url = try await upload(bytes, mime, context)
            guard self.generation == generation, current() == context, !Task.isCancelled else { return }
            guard PlayExperienceService.validHTTPS(url) else { throw PlayExperienceError.malformed }
            uploadedPhoto = .photo(uploadedURL: url)
        } catch { if self.generation == generation, current() == context { issue = error as? PlayExperienceError ?? .unknownResult } }
    }
    public func reviewedPhoto() -> PlayCompletionEvidence? {
        guard capturedContext == current(), !busy else { return nil }; return uploadedPhoto
    }
    public var supportsLibraryPhotos: Bool { supports(.photo) && provider is any PlayKitPhotoLibraryProviding }
    public var isAuthorizing: Bool { (provider as? any PlayDevicePermissionStateProviding)?.authorizationInFlight == true }
    public func supports(_ kind: PlayDeviceKind) -> Bool { provider.supported.contains(kind) }
    public func capture(_ kind: PlayDeviceKind, photoFilter: PlayPhotoFilter? = nil, cameraFrame: PlayKitPhotoFrame? = nil, usePhotoLibrary: Bool = false) async {
        guard !busy, let context = current(), supports(kind) else { issue = .unsupported; return }
        generation &+= 1; let generation = generation; busy = true; output = nil; uploadedPhoto = nil; capturedContext = nil; issue = nil
        defer { if self.generation == generation { busy = false } }
        do {
            var result: PlayDeviceOutput
            if usePhotoLibrary {
                guard kind == .photo, let library = provider as? any PlayKitPhotoLibraryProviding else { throw PlayExperienceError.unsupported }
                result = try await library.captureLibraryPhoto(context: context)
            } else if kind == .photo, let cameraFrame, let framed = provider as? any PlayKitFramedPhotoProviding {
                result = try await framed.capturePhoto(frame: cameraFrame, context: context)
            } else {
                // Framing is optional assistance, never a gate on ordinary evidence.
                result = try await provider.capture(kind, context: context)
            }
            if let photoFilter {
                guard kind == .photo, case .photo(let bytes, _) = result, let filter else { throw PlayExperienceError.unsupported }
                result = .photo(try filter(bytes, photoFilter), mimeType: "image/png")
            }
            guard self.generation == generation, current() == context, !Task.isCancelled else { return }
            output = result; capturedContext = context
        } catch {
            if self.generation == generation, current() == context {
                issue = error is CancellationError ? nil : (error as? PlayExperienceError ?? .unknownResult)
            }
        }
        if self.generation == generation { busy = false }
    }
    public func cancel() { generation &+= 1; provider.cancel(); output = nil; uploadedPhoto = nil; capturedContext = nil; busy = false }
}
