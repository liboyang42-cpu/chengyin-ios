import Foundation

/// Device measurements are evidence for the server, never a completion or reward.
/// Monotonic time cannot be changed by adjusting the device wall clock.
public struct PlayKitTimingRun: Equatable {
    public enum Phase: String { case idle, running, measured, interrupted }
    public private(set) var phase = Phase.idle
    public private(set) var elapsedMilliseconds = 0
    private var startedAt: TimeInterval?
    public init() {}
    public mutating func beginAfterAcknowledgement(now: TimeInterval) {
        guard now.isFinite, now >= 0 else { return }
        startedAt = now; elapsedMilliseconds = 0; phase = .running
    }
    public func elapsed(now: TimeInterval) -> Int {
        guard phase == .running, let startedAt, now.isFinite, now >= startedAt else { return elapsedMilliseconds }
        return Int(min(3_600_000, ((now - startedAt) * 1000).rounded(.down)))
    }
    public mutating func measure(now: TimeInterval) {
        guard phase == .running, let startedAt, now.isFinite, now >= startedAt else { return }
        elapsedMilliseconds = elapsed(now: now); self.startedAt = nil; phase = .measured
    }
    public mutating func interrupt() { if phase == .running { startedAt = nil; elapsedMilliseconds = 0; phase = .interrupted } }
}

public struct PlayKitReactionRun: Equatable {
    public enum Phase: String { case idle, waiting, signal, early, betweenRounds, measured, interrupted }
    public private(set) var phase = Phase.idle
    public private(set) var roundsMilliseconds: [Int] = []
    public let rounds: Int
    private var waitUntil: TimeInterval?
    private var signalAt: TimeInterval?
    public init(rounds: Int) { self.rounds = min(100, max(1, rounds)) }
    public mutating func beginAfterAcknowledgement(now: TimeInterval, randomUnit: Double) {
        roundsMilliseconds = []; phase = .idle; arm(now: now, randomUnit: randomUnit)
    }
    public mutating func arm(now: TimeInterval, randomUnit: Double) {
        guard [.idle, .early, .betweenRounds].contains(phase), now.isFinite, randomUnit.isFinite else { return }
        waitUntil = now + (1.4 + min(1, max(0, randomUnit)) * 2.8); signalAt = nil; phase = .waiting
    }
    public mutating func tick(now: TimeInterval) {
        guard phase == .waiting, let waitUntil, now.isFinite, now >= waitUntil else { return }
        // The response starts when the cue is actually presented, not a missed timer deadline.
        signalAt = now; self.waitUntil = nil; phase = .signal
    }
    public mutating func tap(now: TimeInterval) {
        if phase == .waiting { waitUntil = nil; phase = .early; return }
        guard phase == .signal, let signalAt, now.isFinite, now >= signalAt else { return }
        let ms = Int(min(60_001, ((now - signalAt) * 1000).rounded(.down)))
        self.signalAt = nil
        guard ms >= 120, ms <= 60_000 else { phase = .early; return }
        roundsMilliseconds.append(ms); phase = roundsMilliseconds.count >= rounds ? .measured : .betweenRounds
    }
    public mutating func interrupt() {
        guard phase != .measured else { return }
        waitUntil = nil; signalAt = nil; roundsMilliseconds = []; phase = .interrupted
    }
}

public enum PlayKitSensorKind: String, CaseIterable { case acceleration, soundPeak, heading }
public enum PlayKitSensorSample: Equatable {
    /// Acceleration is m/s²; native CoreMotion g values must be converted once.
    case acceleration(x: Double, y: Double, z: Double, timestamp: TimeInterval)
    /// Peak linear amplitude in 0...1. No audio bytes are retained or uploaded.
    case soundPeak(Double, timestamp: TimeInterval)
    case heading(Double, accuracy: Double, timestamp: TimeInterval)
}
@MainActor public protocol PlayKitSensorProviding: AnyObject {
    var supported: Set<PlayKitSensorKind> { get }
    func samples(_ kind: PlayKitSensorKind) -> AsyncThrowingStream<PlayKitSensorSample, Error>
    func cancel()
}
@MainActor public final class PlayKitDormantSensorProvider: PlayKitSensorProviding {
    public let supported: Set<PlayKitSensorKind> = []
    public init() {}
    public func samples(_ kind: PlayKitSensorKind) -> AsyncThrowingStream<PlayKitSensorSample, Error> {
        AsyncThrowingStream { $0.finish(throwing: PlayExperienceError.disabled) }
    }
    public func cancel() {}
}

/// Calibration requires real samples. Empty/missing streams never become silent success.
public struct PlayKitQuietRun: Equatable {
    public enum Phase: String { case idle, calibrating, ready, running, measured, interrupted }
    public private(set) var phase = Phase.idle
    public private(set) var level: Double = 0
    public private(set) var warningThreshold: Double = 0.12
    public private(set) var stopThreshold: Double = 0.21
    public private(set) var heldSeconds: Double = 0
    public private(set) var exceeded = false
    public let targetSeconds: Double
    private var calibration: [Double] = []
    private var firstSampleAt: TimeInterval?
    private var lastSampleAt: TimeInterval?
    public init(seconds: Double) { targetSeconds = min(3600, max(1, seconds.isFinite ? seconds : 15)) }
    public mutating func calibrate() { phase = .calibrating; calibration = []; firstSampleAt = nil; lastSampleAt = nil; heldSeconds = 0; exceeded = false }
    public mutating func beginAfterAcknowledgement() { guard phase == .ready else { return }; phase = .running; lastSampleAt = nil; heldSeconds = 0 }
    public mutating func ingest(peak: Double, timestamp: TimeInterval) {
        guard [.calibrating, .running].contains(phase), peak.isFinite, (0...1).contains(peak), timestamp.isFinite, timestamp >= 0 else { return }
        if let lastSampleAt, timestamp <= lastSampleAt { return }
        let previous = lastSampleAt; lastSampleAt = timestamp; level = peak
        if phase == .calibrating {
            if let previous, timestamp - previous > 0.25 { calibration = []; firstSampleAt = nil }
            if firstSampleAt == nil { firstSampleAt = timestamp }
            calibration.append(peak)
            if let firstSampleAt, timestamp - firstSampleAt >= 2, calibration.count >= 10 {
                let sorted = calibration.sorted(), index = min(sorted.count - 1, Int(Double(sorted.count) * 0.8))
                warningThreshold = min(0.5, max(0.12, sorted[index] + 0.06)); stopThreshold = min(0.72, warningThreshold + 0.09)
                phase = .ready; calibration = []
            }
            return
        }
        if peak > stopThreshold { exceeded = true; phase = .measured; return }
        guard let previous else { return }
        guard timestamp - previous <= 0.25 else { interrupt(); return }
        heldSeconds = min(targetSeconds, heldSeconds + min(0.1, timestamp - previous))
        if heldSeconds >= targetSeconds { phase = .measured }
    }
    public mutating func interrupt() { if phase != .measured { phase = .interrupted; calibration = []; firstSampleAt = nil; lastSampleAt = nil; heldSeconds = 0 } }
}

/// Physical board state. The player tilts the device; wall contacts are measured,
/// while passed/submitted remain server-owned. Source board uses 0.05 m/s² tilt scale.
public struct PlayKitBallRun: Equatable {
    public enum Phase: String { case idle, calibrating, ready, running, measured, interrupted }
    public private(set) var phase = Phase.idle
    public private(set) var x = 150.0, y = 210.0
    public private(set) var hits = 0
    public private(set) var elapsedSeconds = 0.0
    public let goal: Int; public let limitSeconds: Double
    private var zeroX = 0.0, zeroY = 0.0, vx = 0.0, vy = 0.0
    private var samples: [(Double, Double)] = []
    private var firstAt: TimeInterval?, lastAt: TimeInterval?, runAt: TimeInterval?
    public init(goal: Int, limitSeconds: Double) { self.goal = min(100_000, max(1, goal)); self.limitSeconds = min(3600, max(0, limitSeconds.isFinite ? limitSeconds : 0)) }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.phase == rhs.phase && lhs.x == rhs.x && lhs.y == rhs.y && lhs.hits == rhs.hits && lhs.elapsedSeconds == rhs.elapsedSeconds && lhs.goal == rhs.goal && lhs.limitSeconds == rhs.limitSeconds
    }
    public mutating func calibrate() { phase = .calibrating; samples = []; firstAt = nil; lastAt = nil; hits = 0; x = 150; y = 210; vx = 0; vy = 0 }
    public mutating func beginAfterAcknowledgement() { guard phase == .ready else { return }; phase = .running; lastAt = nil; runAt = nil; elapsedSeconds = 0 }
    public mutating func ingest(x ax: Double, y ay: Double, timestamp: TimeInterval, randomUnit: Double) {
        guard [.calibrating, .running].contains(phase), [ax, ay, timestamp, randomUnit].allSatisfy(\.isFinite), timestamp >= 0 else { return }
        if let lastAt, timestamp <= lastAt { return }
        let previous = lastAt; lastAt = timestamp
        if phase == .calibrating {
            if let previous, timestamp - previous > 0.25 { samples = []; firstAt = nil }
            if firstAt == nil { firstAt = timestamp }
            samples.append((ax, ay))
            if let firstAt, timestamp - firstAt >= 1.2, samples.count >= 10 {
                zeroX = samples.map { $0.0 }.reduce(0,+) / Double(samples.count)
                zeroY = samples.map { $0.1 }.reduce(0,+) / Double(samples.count); samples = []; phase = .ready
            }
            return
        }
        if runAt == nil { runAt = timestamp }
        guard let previous, let runAt else { return }
        guard timestamp - previous <= 0.25 else { interrupt(); return }
        elapsedSeconds = timestamp - runAt
        let frames = min(3, (timestamp - previous) / 0.016)
        vx = (vx - (ax - zeroX) * 0.05 * frames) * pow(0.999, frames)
        vy = (vy + (ay - zeroY) * 0.05 * frames) * pow(0.999, frames)
        x += vx * frames; y += vy * frames
        let jitter = (min(1, max(0, randomUnit)) - 0.5) * 0.5
        if x < 13 || x > 287 { x = min(287, max(13, x)); vx = -vx * 0.98 + jitter; hits += 1 }
        if y < 13 || y > 407 { y = min(407, max(13, y)); vy = -vy * 0.98 - jitter; hits += 1 }
        if hits >= goal || (limitSeconds > 0 && elapsedSeconds >= limitSeconds) { phase = .measured }
    }
    public mutating func interrupt() { if phase != .measured { phase = .interrupted; samples = []; firstAt = nil; lastAt = nil; runAt = nil; hits = 0 } }
}
