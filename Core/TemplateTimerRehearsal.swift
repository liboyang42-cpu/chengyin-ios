import Foundation

/// Author-only elapsed-time inspection. No player evidence, verdict, or reward.
public struct TemplateTimerRehearsal: Equatable {
    public enum Kind: String, CaseIterable, Identifiable {
        case countdown, stopwatch
        public var id: String { rawValue }
        public var labelKey: String { "templateTimer.kind." + rawValue }
    }
    public enum Mode: Equatable { case currentConfiguration, sourceExample }
    public enum Phase: Equatable { case ready, running, paused, finished, result, aborted }
    public enum AbortReason: Equatable { case clock, timeout }
    public enum Tier: String { case excellent, withinTolerance, missed }
    public enum Timing: String { case exact, early, late }
    public struct Result: Equatable {
        public let elapsedMs: Double
        public let deviationSeconds: Double
        public let matched: Bool
        public let tier: Tier
        public let timing: Timing
    }
    public let draft: TemplateAdvancedDraft
    public let kind: Kind
    public let mode: Mode
    public let kicker: String
    public let targetSeconds: Double
    public let toleranceMs: Double
    public let tries: Int
    public let doneText: String
    public let filledFields: [String]
    public private(set) var phase: Phase = .ready
    public private(set) var elapsedMs = 0.0
    public private(set) var result: Result?
    public private(set) var abortReason: AbortReason?
    public private(set) var misses = 0
    public private(set) var round = 1
    private var anchor: Double?
    private var accumulatedMs = 0.0
    private var lastClock: Double?

    public init?(_ original: TemplateAdvancedDraft, kind: Kind, mode: Mode) {
        guard var fields = original.value[kind.rawValue]?.object else { return nil }
        var filled: [String] = []
        if mode == .sourceExample {
            guard let defaults = TemplateAdvancedDraft.defaults[kind.rawValue]?.object,
                  let demos = try? JSONDecoder().decode([String: [String: TemplateAuthoringJSON]].self, from: Data(Self.demoJSON.utf8)),
                  let demo = demos[kind.rawValue] else { return nil }
            for key in demo.keys.sorted() {
                guard let current = fields[key], let expected = defaults[key], let bytes = Self.bytes(current),
                      bytes == Self.bytes(expected), let example = demo[key] else { continue }
                fields[key] = example; filled.append(key)
            }
            fields["enabled"] = .bool(true)
        }
        func text(_ key: String) -> String? {
            guard let raw = fields[key] else { return "" }
            guard let value = raw.string else { return nil }
            return TemplateAuthoringStory.sourceTrim(value)
        }
        func number(_ key: String, _ range: ClosedRange<Double>) -> Double? {
            guard let value = fields[key]?.number, value.isFinite, range.contains(value) else { return nil }
            if let raw = fields[key]?.string, TemplateAuthoringStory.sourceTrim(raw).isEmpty { return nil }
            return value
        }
        guard let title = text("kicker"), title.utf16.count <= 32 else { return nil }
        let target: Double, tolerance: Double, limit: Int, done: String
        if kind == .countdown {
            guard let seconds = number("seconds", 5...3600), let value = text("doneText"), !value.isEmpty, value.utf16.count <= 60 else { return nil }
            target = seconds; tolerance = 0; limit = 0; done = value
        } else {
            guard let seconds = number("targetSeconds", 3...120), let toleranceValue = number("toleranceMs", 50...5000),
                  let attempts = number("tries", 0...10), attempts.rounded() == attempts else { return nil }
            target = seconds; tolerance = toleranceValue; limit = Int(attempts); done = ""
        }
        var copy = original; copy.value[kind.rawValue] = .object(fields)
        draft = copy; self.kind = kind; self.mode = mode
        kicker = title.isEmpty ? (kind == .countdown ? "倒计时" : "把手机拿到面前,随时可以开始") : title
        targetSeconds = target; toleranceMs = tolerance; tries = limit; doneText = done; filledFields = filled
    }
    public var remainingSeconds: Int { max(0, Int(ceil(targetSeconds - elapsedMs / 1000))) }
    public var progress: Double { min(1, max(0, (elapsedMs / (targetSeconds * 1000) * 100).rounded() / 100)) }
    public var isMasked: Bool { kind == .stopwatch && (phase == .running || phase == .paused) && elapsedMs >= 1000 }
    public var triesRemaining: Int? { tries == 0 ? nil : max(0, tries - misses) }
    public var canStart: Bool {
        if phase == .ready { return true }
        if phase == .aborted { return abortReason == .timeout }
        if kind == .countdown { return phase == .finished }
        return phase == .result && result?.matched == false && (triesRemaining == nil || triesRemaining! > 0)
    }
    public var canPauseResume: Bool { kind == .stopwatch && (phase == .running || phase == .paused) }
    public var canStop: Bool { kind == .stopwatch && phase == .running }

    public mutating func start(at now: Double) {
        guard canStart else { return }
        guard now.isFinite, now >= 0 else { abort(.clock); return }
        if phase == .result { round += 1 }
        phase = .running; anchor = now; lastClock = now; accumulatedMs = 0; elapsedMs = 0; result = nil; abortReason = nil
    }
    public mutating func tick(at now: Double) {
        guard phase == .running, let anchor else { return }
        guard validClock(now), now >= anchor else { abort(.clock); return }
        lastClock = now; elapsedMs = accumulatedMs + (now - anchor)
        guard elapsedMs.isFinite else { abort(.clock); return }
        if kind == .countdown, elapsedMs >= targetSeconds * 1000 {
            elapsedMs = targetSeconds * 1000; phase = .finished; self.anchor = nil
        } else if kind == .stopwatch, elapsedMs > (targetSeconds + 30) * 1000 { abort(.timeout) }
    }
    public mutating func pause(at now: Double) {
        guard kind == .stopwatch, phase == .running else { return }
        tick(at: now); guard phase == .running else { return }
        accumulatedMs = elapsedMs; anchor = nil; phase = .paused
    }
    public mutating func resume(at now: Double) {
        guard kind == .stopwatch, phase == .paused else { return }
        guard validClock(now) else { abort(.clock); return }
        anchor = now; lastClock = now; phase = .running
    }
    public mutating func stop(at now: Double) {
        guard canStop else { return }
        tick(at: now); guard phase == .running else { return }
        // Match the source's seconds-based tolerance comparison and strict 5ms wording threshold.
        let diff = abs(elapsedMs / 1000 - targetSeconds), tolerance = toleranceMs / 1000
        let matched = diff <= tolerance, fine = min(0.05, tolerance / 2)
        result = .init(elapsedMs: elapsedMs, deviationSeconds: diff, matched: matched,
                       tier: diff <= fine ? .excellent : (matched ? .withinTolerance : .missed),
                       timing: diff < 0.005 ? .exact : (elapsedMs / 1000 > targetSeconds ? .late : .early))
        if !matched { misses += 1 }
        anchor = nil; phase = .result
    }
    public mutating func reset() {
        phase = .ready; elapsedMs = 0; result = nil; abortReason = nil; misses = 0; round = 1
        anchor = nil; lastClock = nil; accumulatedMs = 0
    }
    private func validClock(_ now: Double) -> Bool { now.isFinite && now >= 0 && (lastClock == nil || now >= lastClock!) }
    private mutating func abort(_ reason: AbortReason) {
        phase = .aborted; abortReason = reason; elapsedMs = 0; result = nil; anchor = nil; lastClock = nil; accumulatedMs = 0
    }
    private static func bytes<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }
    private static let demoJSON = #"""
{"countdown":{"kicker":"一钟油","doneText":"时间到。"},"stopwatch":{"kicker":"盲停在 10 秒"}}
"""#
}
