import Foundation
import Observation

/// Only explicit UI operations mutate the remote registry or request an SDK key.
/// Pending proof bytes are written durably before enroll; recovery never creates
/// another key or revokes an existing key in the background.
@available(macOS 14.0, *)
@MainActor @Observable public final class NativeEnrollmentCoordinator {
    public let scope: NativeEnrollmentScope
    public private(set) var record: NativeEnrollmentRecord?
    public private(set) var status: NativeEnrollmentStatus?
    public private(set) var phase = "idle"
    public private(set) var issue: NativeEnrollmentIssue?
    public let creationAllowed: Bool
    public let revocationAllowed: Bool
    private let enabled: Bool
    private let store: any NativeEnrollmentStoring
    private let service: any NativeEnrollmentServing
    private let device: any NativeEnrollmentDeviceProviding
    private let current: () -> Bool
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private var generation = UUID()
    private var busy = false
    public init(scope: NativeEnrollmentScope, store: any NativeEnrollmentStoring, service: any NativeEnrollmentServing,
                device: any NativeEnrollmentDeviceProviding, enabled: Bool = false, creationAllowed: Bool = false,
                revocationAllowed: Bool = false, current: @escaping () -> Bool,
                now: @escaping () -> Date = Date.init, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.scope = scope; self.store = store; self.service = service; self.device = device; self.enabled = enabled
        self.creationAllowed = creationAllowed; self.revocationAllowed = revocationAllowed; self.current = current; self.now = now; self.uptime = uptime
    }
    public var supported: Bool { enabled && device.supported }
    public var activeKeyID: String? {
        guard current(), !busy, phase == "active", status?.enabled == true, status?.state == .active,
              status?.deviceKeyID == record?.deviceKeyID else { return nil }
        return record?.deviceKeyID
    }
    public var canCreate: Bool {
        enabled && creationAllowed && supported && current() && !busy &&
        (record == nil || phase == "recovery" || phase == "revoked") &&
        status?.enabled == true && (status?.state == .unenrolled || status?.state == .revoked) &&
        record?.phase != .enrolling && record?.phase != .revoking
    }
    public var canResumePreparation: Bool {
        enabled && creationAllowed && supported && current() && !busy && status?.state == .unenrolled &&
        (record?.phase == .keyReady || record?.phase == .requestingChallenge)
    }
    public var canSubmit: Bool { enabled && creationAllowed && current() && !busy && phase == "review" && record?.proof != nil }
    public var canRetryEnrollment: Bool { enabled && creationAllowed && current() && !busy && record?.phase == .enrolling && record?.proof != nil }
    public var canRetryRevocation: Bool { enabled && current() && !busy && record?.phase == .revoking && revocationAllowed }
    public var canRevoke: Bool { activeKeyID != nil && revocationAllowed }

    public func load() async {
        guard enabled, current(), !busy else { if !enabled { phase = "disabled" }; return }
        do {
            record = try store.read(scope: scope); try record?.validate(scope: scope)
            await refreshStatus()
        } catch { fail(NativeEnrollmentIssue.storageUnavailable) }
    }
    public func refreshStatus() async {
        guard enabled, current(), !busy else { return }
        busy = true; let token = generation; issue = nil
        defer { if token == generation { busy = false } }
        do {
            record = try store.read(scope: scope); try record?.validate(scope: scope)
            let result = try await service.status(key: record?.deviceKeyID)
            guard current(), token == generation else { return }
            try acceptStatus(result)
        } catch { if token == generation { fail(error) } }
    }
    /// Opt-in authorizes SDK key creation and Apple attestation preparation only.
    /// The proof remains local until the separate reviewed submit action.
    public func prepareNewKey() async {
        guard canCreate else { return }
        busy = true; let token = generation; issue = nil
        let anchor = NativePlatformClockAnchor(wall: now(), uptime: uptime())
        defer { if token == generation { busy = false } }
        do {
            let checked = try await service.status(key: record?.deviceKeyID)
            guard current(), generation == token, !Task.isCancelled else { return }
            guard checked.enabled, checked.state == .unenrolled || checked.state == .revoked else { throw NativeEnrollmentIssue.disabled }
            var retired = record?.retiredKeys ?? []
            if let old = record?.deviceKeyID { retired.append(old) }
            var next = NativeEnrollmentRecord(scope: scope, retiredKeys: retired)
            try save(next); phase = "generating"
            let key = try await device.generateKey()
            guard NativeEnrollmentWire.validKey(key), !retired.contains(key) else { throw NativeEnrollmentIssue.invalidContract }
            next.deviceKeyID = key; next.phase = .keyReady
            // SDK callbacks cannot be cancelled. Preserve the opaque handle for
            // its ORIGINAL scope even if logout/background happened meanwhile.
            try preserveSDKResult(next)
            guard current(), generation == token, !Task.isCancelled else { return }
            record = next
            try await prepareProof(next, token: token, anchor: anchor)
        } catch { if generation == token { fail(error) } }
    }
    public func prepareSavedKey() async {
        guard canResumePreparation, let next = record, let key = next.deviceKeyID else { return }
        busy = true; let token = generation; issue = nil
        defer { if token == generation { busy = false } }
        do {
            let checked = try await service.status(key: key)
            guard current(), token == generation, checked.enabled, checked.state == .unenrolled else { throw NativeEnrollmentIssue.staleSession }
            try await prepareProof(next, token: token, anchor: .init(wall: now(), uptime: uptime()))
        } catch { if token == generation { fail(error) } }
    }
    private func prepareProof(_ saved: NativeEnrollmentRecord, token: UUID, anchor: NativePlatformClockAnchor) async throws {
        var next = saved
        guard let key = next.deviceKeyID else { throw NativeEnrollmentIssue.invalidContract }
        // A new challenge for the SAME saved key is an explicit recovery action.
        // It is not described as an idempotent retry of an unknown challenge.
        next.phase = .requestingChallenge; try save(next); phase = "preparing"
        let challenge = try await service.challenge(key: key)
        guard current(), generation == token, !Task.isCancelled else { return }
        try anchor.validate(wall: now(), uptime: uptime()); try challenge.validate(now: now())
        guard challenge.deviceKeyID == key, let bytes = challenge.nonce else { throw NativeEnrollmentIssue.invalidContract }
        next.challenge = challenge; next.phase = .attesting; try save(next); phase = "attesting"
        let attestation = try await device.attest(key: key, challengeBytes: bytes)
        next.proof = try .init(deviceKeyID: key, challengeID: challenge.challengeID, attestationObject: attestation)
        next.phase = .review; try preserveSDKResult(next)
        guard current(), generation == token, !Task.isCancelled else { return }
        record = next
        try anchor.validate(wall: now(), uptime: uptime()); try challenge.validate(now: now()); phase = "review"
    }
    public func submitReviewed() async {
        guard canSubmit, let challenge = record?.challenge else { return }
        do { try challenge.validate(now: now()) } catch { fail(error); return }
        await sendEnrollment(isRetry: false)
    }
    public func retryExactEnrollment() async {
        guard canRetryEnrollment else { return }; await sendEnrollment(isRetry: true)
    }
    private func sendEnrollment(isRetry: Bool) async {
        guard var next = record, let proof = next.proof, current(), !busy else { return }
        busy = true; let token = generation; issue = nil
        defer { if token == generation { busy = false } }
        do {
            if !isRetry { next.phase = .enrolling; try save(next) }
            phase = "enrolling"
            _ = try await service.enroll(proof)
            guard current(), token == generation else { return }
            // A matching authoritative GET also covers a lost POST response.
            let result = try await service.status(key: proof.deviceKeyID)
            guard current(), token == generation else { return }
            guard result.state == .active || result.state == .revoked else { throw NativeEnrollmentIssue.unknownResult }
            try acceptStatus(result)
        } catch {
            if token == generation {
                issue = error as? NativeEnrollmentIssue ?? .unknownResult; phase = "unknown"
                if issue == .rejected || issue == .expired {
                    // Only an explicit scoped server refusal closes ambiguity.
                    // Keep the proof until a newly reviewed operation replaces it.
                    next.phase = .rejected
                    do { try save(next); phase = "recovery" } catch { issue = .storageUnavailable }
                }
            }
        }
    }
    public func revokeReviewed() async { guard canRevoke else { return }; await sendRevocation(isRetry: false) }
    public func retryExactRevocation() async { guard canRetryRevocation else { return }; await sendRevocation(isRetry: true) }
    private func sendRevocation(isRetry: Bool) async {
        guard var next = record, let key = next.deviceKeyID, current(), !busy else { return }
        busy = true; let token = generation; issue = nil
        defer { if token == generation { busy = false } }
        do {
            if !isRetry { next.phase = .revoking; try save(next) }
            phase = "revoking"
            _ = try await service.revoke(key: key)
            guard current(), token == generation else { return }
            let readback = try await service.status(key: key)
            guard current(), token == generation else { return }
            guard readback.state == .revoked else { throw NativeEnrollmentIssue.unknownResult }
            try acceptStatus(readback)
        } catch { if token == generation { issue = error as? NativeEnrollmentIssue ?? .unknownResult; phase = "unknown" } }
    }
    private func acceptStatus(_ result: NativeEnrollmentStatus) throws {
        guard result.deviceKeyID == record?.deviceKeyID else { throw NativeEnrollmentIssue.invalidContract }
        status = result; issue = nil
        guard result.enabled else { phase = "disabled"; return }
        if result.state == .active || result.state == .revoked {
            guard var next = record else { throw NativeEnrollmentIssue.invalidContract }
            if next.phase == .revoked && result.state == .active { throw NativeEnrollmentIssue.invalidContract }
            if next.phase == .revoking && result.state == .active { phase = "unknown"; issue = .unknownResult; return }
            next.phase = result.state == .active ? .active : .revoked
            next.proof = nil; next.challenge = nil; try save(next); phase = result.state == .active ? "active" : "revoked"; return
        }
        guard result.state == .unenrolled else { throw NativeEnrollmentIssue.invalidContract }
        guard let record else { phase = "ready"; return }
        switch record.phase {
        case .enrolling, .revoking: phase = "unknown"; issue = .unknownResult
        case .review:
            do {
                guard let challenge = record.challenge else { throw NativeEnrollmentIssue.invalidContract }
                try challenge.validate(now: now()); phase = "review"
            } catch { phase = "recovery"; issue = .expired }
        default: phase = "recovery"; issue = .keyRecoveryRequired
        }
    }
    private func preserveSDKResult(_ next: NativeEnrollmentRecord) throws {
        try next.validate(scope: scope)
        guard var existing = try store.read(scope: scope) else { throw NativeEnrollmentIssue.storageUnavailable }
        if existing.operationID == next.operationID { try store.write(next) }
        else if let key = next.deviceKeyID, existing.deviceKeyID != key, !existing.retiredKeys.contains(key) {
            // An explicitly newer enrollment may not be overwritten by a late
            // callback. Retain the superseded handle as non-reusable history.
            existing.retiredKeys.append(key); try existing.validate(scope: scope); try store.write(existing)
        }
    }
    private func save(_ next: NativeEnrollmentRecord) throws {
        try next.validate(scope: scope)
        do { try store.write(next) } catch { throw NativeEnrollmentIssue.storageUnavailable }
        record = next
    }
    /// Cancels only local work. This never revokes the remote key or deletes its
    /// durable pending proof. The same account can explicitly recover after login.
    public func pauseWork() { if busy { suspend() } }
    public func suspend() { generation = UUID(); device.cancel(); busy = false; status = nil; phase = "recovery" }
    public func invalidate() { suspend(); record = nil; issue = .staleSession; phase = "stale" }
    private func fail(_ error: Error) {
        if error is NativePlatformIssue { issue = .clockChanged }
        else { issue = error as? NativeEnrollmentIssue ?? .network }
        phase = record == nil ? "failed" : "recovery"
    }
}
