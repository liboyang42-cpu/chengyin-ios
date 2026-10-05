import Foundation

/// Receipt time and sensor time are both monotonic. A display timer can only
/// detect a missing stream; it never manufactures a sensor sample or earned time.
public struct PlayKitSensorContinuity: Equatable {
    public static let maximumGap: TimeInterval = 0.25
    public let kind: PlayKitSensorKind
    private var beganAt: TimeInterval
    private var lastReceivedAt: TimeInterval?
    private var lastTimestamp: TimeInterval?
    public init(kind: PlayKitSensorKind, now: TimeInterval) { self.kind = kind; beganAt = now }
    public mutating func accept(_ sample: PlayKitSensorSample, now: TimeInterval) -> Bool {
        let timestamp: TimeInterval
        switch (kind, sample) {
        case let (.acceleration, .acceleration(x, y, z, time)):
            guard [x, y, z].allSatisfy(\.isFinite) else { return false }; timestamp = time
        case let (.soundPeak, .soundPeak(peak, time)):
            guard peak.isFinite, (0...1).contains(peak) else { return false }; timestamp = time
        case let (.heading, .heading(bearing, accuracy, time)):
            guard bearing.isFinite, (0..<360).contains(bearing), accuracy.isFinite, accuracy >= 0 else { return false }; timestamp = time
        default: return false
        }
        guard now.isFinite, timestamp.isFinite, timestamp >= 0, now >= beganAt,
              timestamp >= beganAt, now - timestamp <= Self.maximumGap,
              timestamp - now <= 0.05 else { return false }
        if let lastTimestamp, timestamp <= lastTimestamp { return false }
        if let lastTimestamp, timestamp - lastTimestamp > Self.maximumGap { return false }
        lastTimestamp = timestamp; lastReceivedAt = now; return true
    }
    public func expired(now: TimeInterval) -> Bool {
        guard now.isFinite, now >= beganAt else { return true }
        // Permission UI may take time, but once samples arrive, a stalled stream
        // interrupts promptly. Native providers perform permission before yielding.
        return now - (lastReceivedAt ?? beganAt) > (lastReceivedAt == nil ? 3 : Self.maximumGap)
    }
}

/// A compass attempt has no START_CHALLENGE. The only submit value is an actual
/// measured magnetic bearing, after a continuous fresh, accurate, aligned hold.
public struct PlayKitCompassRun: Equatable {
    public enum Phase: String { case idle, running, measured, interrupted }
    public private(set) var phase = Phase.idle
    public let target: Double
    public let tolerance: Double
    public let holdSeconds: Double
    public private(set) var heading: Double?
    public private(set) var accuracy: Double?
    public private(set) var aligned = false
    public private(set) var lowAccuracy = false
    public private(set) var heldSeconds = 0.0
    public private(set) var needleDegrees = 0.0
    public private(set) var roseDegrees = 0.0
    private var lastAt: TimeInterval?
    public init(target: Double, tolerance: Double, holdSeconds: Double) {
        self.target = Self.normalized(target.isFinite ? target : 0)
        self.tolerance = min(180, max(1, tolerance.isFinite && tolerance > 0 ? tolerance : 15))
        self.holdSeconds = min(3600, max(1, holdSeconds.isFinite && holdSeconds > 0 ? holdSeconds : 3))
    }
    public mutating func begin() {
        phase = .running; heading = nil; accuracy = nil; heldSeconds = 0; lastAt = nil
        aligned = false; lowAccuracy = false; needleDegrees = 0; roseDegrees = 0
    }
    public mutating func ingest(bearing: Double, accuracy: Double, timestamp: TimeInterval) {
        guard phase == .running, [bearing, accuracy, timestamp].allSatisfy(\.isFinite),
              (0..<360).contains(bearing), timestamp >= 0 else { return }
        if let lastAt, timestamp <= lastAt { return }
        if let lastAt, timestamp - lastAt > PlayKitSensorContinuity.maximumGap { interrupt(); return }
        let previous = lastAt, wasAligned = aligned, previousHeading = heading
        lastAt = timestamp; heading = bearing; self.accuracy = accuracy
        lowAccuracy = accuracy < 0 || accuracy > tolerance
        aligned = !lowAccuracy && Self.angleDifference(bearing, target) <= tolerance
            && Self.angleDifference(Self.normalized(bearing.rounded()), target) <= tolerance
        needleDegrees = Self.continuous(target - bearing, previous: previousHeading == nil ? nil : needleDegrees)
        roseDegrees = Self.continuous(-bearing, previous: previousHeading == nil ? nil : roseDegrees)
        if aligned, wasAligned, let previous {
            heldSeconds = min(holdSeconds, heldSeconds + min(0.1, timestamp - previous))
        } else { heldSeconds = 0 }
        if heldSeconds >= holdSeconds { phase = .measured }
    }
    /// Rounding must still be within tolerance; do not replace the reading with
    /// the configured target, including when a real bearing is exactly north.
    public var submittedBearing: Int? {
        guard phase == .measured, let heading else { return nil }
        let rounded = Int(Self.normalized(heading.rounded()))
        guard Self.angleDifference(Double(rounded), target) <= tolerance else { return nil }
        return rounded
    }
    public var signedDelta: Double { Self.normalized(target - (heading ?? target) + 180) - 180 }
    public mutating func interrupt() {
        guard phase != .measured else { return }
        phase = .interrupted; heldSeconds = 0; lastAt = nil; aligned = false
    }
    public static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }
    public static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let delta = abs(normalized(a - b)); return min(delta, 360 - delta)
    }
    public static func continuous(_ degrees: Double, previous: Double?) -> Double {
        let value = normalized(degrees)
        guard let previous, previous.isFinite else { return value }
        return previous + normalized(value - previous + 180) - 180
    }
}

/// Continuous loudness uses the same live two-second baseline as quiet hold.
/// Falling to or below the hot threshold clears the whole hold, never banks time.
public struct PlayKitShoutRun: Equatable {
    public enum Phase: String { case idle, calibrating, ready, running, measured, interrupted }
    public private(set) var phase = Phase.idle
    public private(set) var level = 0.0
    public private(set) var heldSeconds = 0.0
    public private(set) var loud = false
    public let targetSeconds: Double
    public var warningThreshold: Double { calibration.warningThreshold }
    public var loudThreshold: Double { calibration.stopThreshold }
    private var calibration: PlayKitQuietRun
    private var lastAt: TimeInterval?
    public init(seconds: Double) {
        targetSeconds = min(3600, max(1, seconds.isFinite && seconds > 0 ? seconds : 5))
        calibration = PlayKitQuietRun(seconds: targetSeconds)
    }
    public mutating func calibrate() {
        calibration.calibrate(); phase = .calibrating; heldSeconds = 0; level = 0; loud = false; lastAt = nil
    }
    public mutating func beginAfterAcknowledgement() {
        guard phase == .ready else { return }
        phase = .running; heldSeconds = 0; loud = false; lastAt = nil
    }
    public mutating func ingest(peak: Double, timestamp: TimeInterval) {
        guard [.calibrating, .running].contains(phase), peak.isFinite, (0...1).contains(peak), timestamp.isFinite, timestamp >= 0 else { return }
        if phase == .calibrating {
            calibration.ingest(peak: peak, timestamp: timestamp); level = calibration.level
            if calibration.phase == .ready { phase = .ready }
            return
        }
        if let lastAt, timestamp <= lastAt { return }
        if let lastAt, timestamp - lastAt > PlayKitSensorContinuity.maximumGap { interrupt(); return }
        let previous = lastAt, wasLoud = loud
        lastAt = timestamp; level = peak; loud = peak > loudThreshold
        if loud, wasLoud, let previous { heldSeconds = min(targetSeconds, heldSeconds + min(0.1, timestamp - previous)) }
        else { heldSeconds = 0 }
        if heldSeconds >= targetSeconds { phase = .measured }
    }
    public mutating func interrupt() {
        guard phase != .measured else { return }
        calibration.interrupt(); phase = .interrupted; heldSeconds = 0; loud = false; lastAt = nil
    }
}

/// Optional authorization phase keeps a system permission sheet separate from
/// sample freshness checks. Invoke only after explaining the sensor purpose.
@MainActor public protocol PlayKitSensorAuthorizing: AnyObject {
    func prepare(_ kind: PlayKitSensorKind) async throws
}

public enum PlayKitSensorError: String, Error, Equatable {
    case configurationUnavailable, permissionDenied, sensorUnavailable, interrupted, missingSamples
}

/// Quiet's host contract takes seconds and converts to heldMs exactly once.
/// Preserve sample precision here; the shared catalog owns millisecond rounding.
extension PlayKitQuietRun {
    public var reviewDetail: [String: PlayWireValue]? {
        guard phase == .measured else { return nil }
        return ["heldSeconds": .number(heldSeconds)]
    }
}
