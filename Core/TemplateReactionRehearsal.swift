import Foundation

/// Author-local inspection only. These readings are never player evidence or task results.
public struct TemplateReactionRehearsal: Equatable {
    public enum Mode: Equatable { case currentConfiguration, sourceExample }
    public enum Phase: Equatable { case idle, waiting, signal, early, finished, aborted }
    public enum EarlyReason: Equatable { case beforeSignal, belowHumanMinimum }
    public let draft: TemplateAdvancedDraft
    public let mode: Mode
    public let kicker: String
    public let rounds: Int
    public let goalMs: Double
    public let filledFields: [String]
    public private(set) var phase: Phase = .idle
    public private(set) var times: [Double] = []
    public private(set) var earlyReason: EarlyReason?
    public private(set) var waitUntil: Double?
    private var signalAt: Double?
    private var lastClock: Double?

    public init?(_ original: TemplateAdvancedDraft, mode: Mode) {
        guard var fields = original.value["reaction"]?.object else { return nil }
        var filled: [String] = []
        if mode == .sourceExample {
            if let current = fields["kicker"], let expected = TemplateAdvancedDraft.defaults["reaction"]?.object?["kicker"],
               let bytes = Self.bytes(current), bytes == Self.bytes(expected) {
                fields["kicker"] = .string("屏幕一变色就点"); filled.append("kicker")
            }
            fields["enabled"] = .bool(true)
        }
        let rawTitle: String
        if let field = fields["kicker"] { guard let text = field.string else { return nil }; rawTitle = text }
        else { rawTitle = "" }
        let title = TemplateAuthoringStory.sourceTrim(rawTitle)
        func number(_ key: String, _ range: ClosedRange<Double>) -> Double? {
            guard let value = fields[key]?.number, value.isFinite, range.contains(value) else { return nil }
            if let raw = fields[key]?.string, TemplateAuthoringStory.sourceTrim(raw).isEmpty { return nil }
            return value
        }
        // Existing native allows 3000ms; source validation allows 2000ms. This leaf uses their intersection.
        guard title.utf16.count <= 32, let count = number("rounds", 1...10), count.rounded() == count,
              let goal = number("goalMs", 120...2000) else { return nil }
        var copy = original; copy.value["reaction"] = .object(fields)
        draft = copy; self.mode = mode; kicker = title.isEmpty ? "变绿就点" : title
        rounds = Int(count); goalMs = goal; filledFields = filled
    }
    public var round: Int { min(times.count + 1, rounds) }
    public var bestMs: Double? { times.min() }
    public var matched: Bool? { phase == .finished ? bestMs.map { $0 <= goalMs } : nil }
    public var canArm: Bool { phase == .idle || phase == .early }
    public var canTap: Bool { canArm || phase == .waiting || phase == .signal }
    public static func waitMilliseconds(unit: Double) -> Double? {
        guard unit.isFinite, (0...1).contains(unit) else { return nil }
        return (1400 + unit * 2800).rounded()
    }
    public mutating func arm(at now: Double, delayUnit: Double) {
        guard canArm else { return }
        guard validClock(now), let delay = Self.waitMilliseconds(unit: delayUnit), (now + delay).isFinite, now + delay > now else { abort(); return }
        lastClock = now; waitUntil = now + delay; signalAt = nil; earlyReason = nil; phase = .waiting
    }
    /// A delayed callback starts the reading at the actual signal, never the nominal deadline.
    public mutating func signal(at now: Double) {
        guard phase == .waiting, let deadline = waitUntil else { return }
        guard validClock(now) else { abort(); return }
        lastClock = now
        guard now >= deadline else { return }
        signalAt = now; waitUntil = nil; phase = .signal
    }
    public mutating func tap(at now: Double) {
        guard phase == .waiting || phase == .signal else { return }
        guard validClock(now) else { abort(); return }
        lastClock = now
        if phase == .waiting { markEarly(.beforeSignal); return }
        guard let signalAt else { abort(); return }
        let elapsed = now - signalAt
        guard elapsed.isFinite, elapsed >= 0 else { abort(); return }
        guard elapsed >= 120 else { markEarly(.belowHumanMinimum); return }
        times.append(elapsed); self.signalAt = nil
        phase = times.count >= rounds ? .finished : .idle
    }
    public mutating func reset() {
        phase = .idle; times = []; earlyReason = nil; waitUntil = nil; signalAt = nil; lastClock = nil
    }
    private func validClock(_ now: Double) -> Bool { now.isFinite && now >= 0 && (lastClock == nil || now >= lastClock!) }
    private mutating func markEarly(_ reason: EarlyReason) {
        phase = .early; earlyReason = reason; waitUntil = nil; signalAt = nil
    }
    private mutating func abort() { phase = .aborted; waitUntil = nil; signalAt = nil; earlyReason = nil }
    private static func bytes(_ value: TemplateAuthoringJSON) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }
}
