import Foundation
import Observation

/// Audit-only sensor workflow with an immutable, correlated retry. It never calls
/// the legacy WeRun action and never derives reached, score or reward from counts.
@available(macOS 14.0, *)
@MainActor @Observable public final class NativeStepCoordinator {
    public private(set) var phase = "idle"
    public private(set) var issue: NativePlatformIssue?
    public private(set) var challenge: NativeStepChallenge?
    public private(set) var reading: NativePedometerReading?
    public private(set) var pending: NativePlatformPending?
    public private(set) var receipt: PlayWireValue?
    public private(set) var latestState: PlayAdvancedState?
    public var permission: NativePlatformPermission { pedometer.permission }
    public var supported: Bool { assertion.supported && pedometer.permission != .unsupported }
    private let owner: PlayExperienceSession
    private let service: any NativePlatformServing
    private let pedometer: any NativePedometerProviding
    private let assertion: any NativeStepAssertionProviding
    private let current: () -> PlayExperienceSession?
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private var generation = UUID()
    private var anchor: NativePlatformClockAnchor?
    public init(owner: PlayExperienceSession, service: any NativePlatformServing,
                pedometer: any NativePedometerProviding, assertion: any NativeStepAssertionProviding,
                current: @escaping () -> PlayExperienceSession?, now: @escaping () -> Date = Date.init,
                uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.owner = owner; self.service = service; self.pedometer = pedometer; self.assertion = assertion
        self.current = current; self.now = now; self.uptime = uptime
    }
    /// Invoked only after the native purpose/legal disclosure and explicit tap.
    public func read(sessionID: Int, version: Int) async {
        guard current() == owner, pending == nil, !["reading", "signing", "submitting"].contains(phase) else { return }
        guard supported else { issue = .unsupported; phase = "blocked"; return }
        switch permission {
        case .denied: issue = .denied; phase = "blocked"; return
        case .restricted: issue = .restricted; phase = "blocked"; return
        default: break
        }
        generation = UUID(); anchor = .init(wall: now(), uptime: uptime()); reading = nil; challenge = nil; receipt = nil
        do {
            pending = try NativePlatformPending(sessionID: sessionID, version: version, key: UUID().uuidString,
                action: .issue, payload: ["provider": .string(NativeStepChallenge.provider), "deviceKeyId": .string(assertion.deviceKeyID)])
            await dispatch()
        } catch { fail(error) }
    }
    public func submitReviewed() async {
        guard current() == owner, phase == "review", pending == nil, let challenge, let reading else { return }
        let token = generation; phase = "signing"
        do {
            try validateClock(); try challenge.validate(reading, now: now())
            let key = UUID().uuidString
            let data = try NativeStepCanonical.clientData(challenge: challenge, reading: reading, idempotencyKey: key)
            let signature = try await assertion.assertion(clientData: data)
            guard current() == owner, generation == token, !Task.isCancelled else { throw NativePlatformIssue.staleSession }
            try validateClock(); try challenge.validate(reading, now: now())
            var payload = challenge.unsignedPayload(reading); payload["assertion"] = .string(signature)
            pending = try NativePlatformPending(sessionID: challenge.sessionID, version: challenge.sessionVersion,
                key: key, action: .submit, payload: payload)
            await dispatch()
        } catch { if generation == token { fail(error) } }
    }
    public func retryExact() async {
        guard phase == "unknown", pending != nil, current() == owner else { return }
        // The identical assertion and idempotency key are retained. The server's
        // receipt lookup runs before nonce consumption; do not regenerate either.
        await dispatch()
    }
    private func dispatch() async {
        guard let request = pending else { return }
        let token = generation; phase = request.action == .issue ? "reading" : "submitting"; issue = nil
        do {
            let state = try await service.action(request)
            guard token == generation, current() == owner, !Task.isCancelled else { return }
            latestState = state
            let native = state.playKit["steps"]["nativeSteps"]
            guard native["protocolVersion"].integer == 1, native["provider"].text == NativeStepChallenge.provider,
                  native["enabled"].bool == true, native["rewardEnabled"].bool == false,
                  native["status"].text == "AUDIT_ONLY", native["accountId"].integer == owner.accountID,
                  native["sessionId"].integer == state.sessionID, native["sessionVersion"].integer == state.version,
                  native["deviceKeyId"].text == assertion.deviceKeyID else { throw NativePlatformIssue.disabled }
            if request.action == .issue {
                let challenge = try NativeStepChallenge(native["challenge"], owner: owner, sessionID: state.sessionID,
                    version: state.version, deviceKeyID: assertion.deviceKeyID)
                pending = nil
                try validateClock(); try challenge.validate(now: now()); self.challenge = challenge
                let end = Date(timeIntervalSince1970: floor(now().timeIntervalSince1970 * 1000) / 1000)
                let sample = try await pedometer.read(from: Date(timeIntervalSince1970: Double(challenge.dayStartAt) / 1000), to: end)
                guard generation == token, current() == owner, !Task.isCancelled else { return }
                try validateClock(); try challenge.validate(sample, now: now())
                reading = sample; phase = "review"
            } else {
                guard let baseline = native["baselineSteps"].integer, (0...100_000).contains(baseline),
                      let delta = native["acceptedDelta"].integer, (0...100_000).contains(delta),
                      native["lastSampleEndAt"].integer == request.payload["sampleEndAt"]?.integer else { throw NativePlatformIssue.invalidContract }
                pending = nil; receipt = native; reading = nil; challenge = nil; anchor = nil; phase = "recorded"
            }
        } catch {
            guard generation == token else { return }
            if pending != nil {
                if case PlayExperienceError.rejected = error { pending = nil; fail(error) }
                else if error as? PlayExperienceError == .disabled || error as? NativePlatformIssue == .disabled || error as? NativePlatformIssue == .staleSession {
                    pending = nil; fail(error)
                } else { phase = "unknown"; issue = .unknownResult }
            } else { fail(error) }
        }
    }
    private func validateClock() throws {
        guard let anchor else { throw NativePlatformIssue.interrupted }
        try anchor.validate(wall: now(), uptime: uptime())
    }
    public func observeVersion(_ version: Int) {
        if let challenge, version != challenge.sessionVersion { interrupt(.windowChanged) }
    }
    public func interrupt(_ reason: NativePlatformIssue = .interrupted) {
        generation = UUID(); pedometer.cancel(); assertion.cancel(); reading = nil; challenge = nil; anchor = nil
        // Ambiguous writes remain frozen and may only be retried by their owner.
        phase = pending == nil ? "interrupted" : "unknown"; issue = reason
    }
    public func invalidate() { interrupt(.staleSession); pending = nil; receipt = nil; latestState = nil; phase = "stale" }
    private func fail(_ error: Error) { reading = nil; challenge = nil; issue = error as? NativePlatformIssue ?? .network; phase = "failed" }
}
