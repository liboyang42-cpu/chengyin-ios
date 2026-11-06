import Foundation
import Observation

/// Reform plan v9 §28 / W19.1, W19.4–W19.6: the player resource account a return-home
/// restore refills. current/max/version are server facts; the client never computes a
/// maximum or a restore amount. Scope is explicit (global or one run/theme).
public struct NativeHomeResourceAccount: Decodable, Equatable, Sendable {
    public let resourceType: String
    public let scopeType: String
    public let scopeId: String?
    public let current, maximum: Int64
    public let version: Int64
    public func validate(for scope: NativeHomeResourceScope) throws {
        var wire = ["scopeType": scopeType, "resourceType": resourceType]
        if let scopeId { wire["scopeId"] = scopeId }
        guard wire == scope.wire, current >= 0, maximum > 0, current <= maximum, ReformWire.version(version) else { throw NativeHomeReturnFailure.invalid }
    }
}

/// Server decision for VerifyReturnHome. Only VERIFIED carries a short-lived proof.
public struct NativeHomeReturnVerification: Decodable, Equatable, Sendable {
    public enum Decision: String, Decodable, Sendable {
        case verified = "VERIFIED", outOfRadius = "OUT_OF_RADIUS", lowAccuracy = "LOW_ACCURACY", staleFix = "STALE_FIX"
        case cooldown = "COOLDOWN", homeChanged = "HOME_CHANGED", noHome = "NO_HOME"
        case dwellRequired = "DWELL_REQUIRED", runUnavailable = "RUN_UNAVAILABLE"
    }
    public let requestId: String
    public let decision: Decision
    public let proofId: String?
    public let homeVersion: Int64
    public let expiresAtMillis: Int64?
    public let retryAfterSeconds: Int?
    public var challengeId: String? = nil
    public var accountVersion: Int64? = nil
    public func validateIdentity(for check: NativeHomeReturnCheck) throws {
        guard requestId == check.requestId, ReformWire.version(homeVersion) else { throw NativeHomeReturnFailure.invalid }
        if decision == .verified || decision == .dwellRequired {
            guard check.expectedAccountVersion == nil || accountVersion == check.expectedAccountVersion else { throw NativeHomeReturnFailure.invalid }
        }
        if decision == .dwellRequired, let originalChallenge = check.challengeId {
            // A continuation reports the same server challenge; it cannot silently replace it.
            guard challengeId == originalChallenge else { throw NativeHomeReturnFailure.invalid }
        }
    }
    /// Maps to a proof or a distinct, understandable failure; never a fake success.
    public func proof(for check: NativeHomeReturnCheck) throws -> NativeHomeReturnProof {
        try validateIdentity(for: check)
        switch decision {
        case .verified:
            guard let proofId, let expiresAtMillis, retryAfterSeconds == nil, challengeId == nil else { throw NativeHomeReturnFailure.invalid }
            return try NativeHomeReturnProof(proofId: proofId, homeVersion: homeVersion, scope: check.scope, expiresAtMillis: expiresAtMillis, for: check)
        case .dwellRequired:
            guard proofId == nil, expiresAtMillis == nil, homeVersion == check.homeVersion,
                  let challengeId, ReformWire.id(challengeId), challengeId.utf8.count <= 64,
                  let retryAfterSeconds, retryAfterSeconds > 0 else { throw NativeHomeReturnFailure.invalid }
            throw NativeHomeReturnFailure.dwellRequired(retryAfterSeconds: retryAfterSeconds)
        case .cooldown:
            guard proofId == nil, expiresAtMillis == nil, challengeId == nil, let retryAfterSeconds, retryAfterSeconds > 0 else { throw NativeHomeReturnFailure.invalid }
            throw NativeHomeReturnFailure.cooldown(retryAfterSeconds: retryAfterSeconds)
        default:
            guard proofId == nil, retryAfterSeconds == nil, expiresAtMillis == nil, challengeId == nil else { throw NativeHomeReturnFailure.invalid }
            switch decision {
            case .outOfRadius: throw NativeHomeReturnFailure.outOfRadius
            case .lowAccuracy: throw NativeHomeReturnFailure.lowAccuracy
            case .staleFix: throw NativeHomeReturnFailure.staleFix
            case .homeChanged: throw NativeHomeReturnFailure.homeChanged
            case .runUnavailable: throw NativeHomeReturnFailure.runUnavailable
            default: throw NativeHomeReturnFailure.noHome
            }
        }
    }
}

/// W19 service seam. Native implementation is independently gated; fixtures remain offline.
@MainActor public protocol NativeHomeReturnServing: AnyObject {
    /// nil means the server publishes no policy: the feature is unavailable.
    func policy() async throws -> NativeHomeReturnPolicy?
    func account(for scope: NativeHomeResourceScope) async throws -> NativeHomeResourceAccount
    func verify(_ check: NativeHomeReturnCheck) async throws -> NativeHomeReturnVerification
    func restore(_ request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt
    func restoreReceipt(for request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt?
}

/// Explicit verification, server dwell, then a separate restore confirmation. Loading never samples or writes.
@available(macOS 14.0, *)
@MainActor @Observable public final class NativeHomeReturnCoordinator {
    public enum Phase: String, Sendable { case disabled, idle, loading, ready, unavailable, checking, restoring, unknown, invalidated, verified, dwelling, blocked }
    public private(set) var phase: Phase = .idle
    public private(set) var account: NativeHomeResourceAccount?
    public private(set) var failure: NativeHomeReturnFailure?
    public private(set) var decision: NativeHomeRestoreReceipt.Decision?
    public private(set) var noReceiptYet = false
    public private(set) var retryAfterSeconds: Int?
    public private(set) var requiresAccountReadback = false
    public let scope: NativeHomeResourceScope
    private var policy: NativeHomeReturnPolicy?
    private var proof: NativeHomeReturnProof?
    private var proofAccountVersion: Int64?
    private var challenge: (id: String, homeVersion: Int64, accountVersion: Int64, policyVersion: String)?
    private var pending: NativeHomeRestoreRequest?
    // A cancelled save may still finish in the vault. Keep that original identity until
    // an explicit recovery checks the durable slot; cancellation never manufactures a new request.
    private var savingRequest: NativeHomeRestoreRequest?
    private var settlingTicket: UUID?
    private var pauseAfterSettlement = false
    // Owner/scope-instance floor from validated current reads and settled original receipts.
    // It is not durable state and is discarded on invalidation, never evidence of a balance.
    private var minimumAccountVersion: Int64?
    private var settledFailure: NativeHomeReturnFailure?
    private let service: (any NativeHomeReturnServing)?
    private let journal: (any NativeHomeReturnSecureJournaling)?
    private let owner: PlayExperienceSession?
    private let native: Bool
    private let location: () async -> NativeHomeReturnLocationStatus
    private let isCurrent: () -> Bool
    private let now: () -> Date
    private let stopLocation: () -> Void
    private let locationAuthorized: () -> Bool
    private var serverOffset: TimeInterval = 0
    private var generation = UUID()

    /// Production construction requires a scoped durable journal and an explicit reviewed grant.
    public init(scope: NativeHomeResourceScope, service: (any NativeHomeReturnServing)?, journal: (any NativeHomeReturnSecureJournaling)?,
                owner: PlayExperienceSession, enabled: Bool = false, location: @escaping () async -> NativeHomeReturnLocationStatus,
                stopLocation: @escaping () -> Void = {}, locationAuthorized: @escaping () -> Bool = { false }, isCurrent: @escaping () -> Bool, now: @escaping () -> Date = { Date() }) {
        self.scope = scope; self.service = service; self.journal = journal; self.owner = owner; native = true
        self.location = location; self.stopLocation = stopLocation; self.locationAuthorized = locationAuthorized; self.isCurrent = isCurrent; self.now = now
        if !enabled || service == nil || journal?.scope != PrivateHomeJournalScope(owner: owner) || (try? scope.validateNative()) == nil { phase = .disabled }
    }
    public var isBusy: Bool { [.loading, .checking, .restoring].contains(phase) }
    public var hasPendingRestore: Bool { pending != nil }
    public var canCheckIn: Bool { [.ready, .dwelling, .verified].contains(phase) && policy != nil && account != nil && pending == nil && !requiresAccountReadback && isCurrent() }
    public var canRestore: Bool { phase == .verified && proof != nil && proofAccountVersion == account?.version && pending == nil && isCurrent() && locationAuthorized() }
    public var canRetryExact: Bool { phase == .unknown && pending != nil && isCurrent() }
    public func invalidate() {
        generation = UUID(); stopLocation(); account = nil; policy = nil; pending = nil; proof = nil; challenge = nil
        proofAccountVersion = nil; failure = nil; settledFailure = nil; decision = nil; noReceiptYet = false; retryAfterSeconds = nil
        requiresAccountReadback = false; minimumAccountVersion = nil; savingRequest = nil
        settlingTicket = nil; pauseAfterSettlement = false; phase = .invalidated
    }
    /// Navigation/background discards ephemeral evidence. It never clears durable UNKNOWN or replays it.
    public func cancelVerification() {
        if phase == .restoring {
            stopLocation(); proof = nil; challenge = nil; proofAccountVersion = nil; retryAfterSeconds = nil
            if settlingTicket == generation {
                // A validated terminal receipt already authorized this exact conditional clear.
                // It may have happened in the vault; do not relabel that known result UNKNOWN.
                pauseAfterSettlement = true; return
            }
            generation = UUID()
            pending = pending ?? savingRequest
            noReceiptYet = false; decision = nil
            failure = pending == nil ? .storageUnavailable : .unknown
            phase = pending == nil ? .blocked : .unknown
            return
        }
        guard !isBusy else {
            if phase == .checking { generation = UUID(); stopLocation(); proof = nil; challenge = nil; proofAccountVersion = nil; phase = .ready }
            return
        }
        if phase == .dwelling { failure = nil }
        proof = nil; challenge = nil; proofAccountVersion = nil; retryAfterSeconds = nil
        if phase == .verified || phase == .dwelling { phase = .ready }
    }
    private func gate() -> Bool {
        guard phase != .disabled, phase != .invalidated else { return false }
        guard isCurrent() else { invalidate(); return false }
        return true
    }
    private func commandIsCurrent(_ ticket: UUID) -> Bool {
        guard ticket == generation, gate() else { return false }
        guard !Task.isCancelled else { cancelVerification(); return false }
        return true
    }
    private func checkJournalScope() throws {
        if native {
            guard let owner, journal?.scope == PrivateHomeJournalScope(owner: owner) else { throw NativeHomeReturnFailure.storageUnavailable }
        }
    }
    public func load() async {
        guard gate(), let service, !isBusy else { return }
        let ticket = generation; phase = .loading
        if decision == nil { failure = nil }
        proof = nil; challenge = nil; proofAccountVersion = nil; retryAfterSeconds = nil
        do {
            try checkJournalScope()
            if let journal {
                let stored = try await journal.read()
                guard ticket == generation, gate() else { return }
                try stored?.validateNative()
                guard stored == nil || stored?.scope == scope else { throw NativeHomeReturnFailure.storageUnavailable }
                // If durable state vanished while this instance was unknown, do not unlock it from a GET.
                guard pending == nil || stored == pending else { throw NativeHomeReturnFailure.storageUnavailable }
                pending = stored
            }
        } catch {
            guard ticket == generation, gate() else { return }
            failure = .storageUnavailable; account = nil; phase = pending == nil ? .blocked : .unknown; return
        }
        do {
            let policyRequestStartedAt = now()
            let published = try await service.policy()
            guard ticket == generation, gate() else { return }
            guard let published else { throw NativeHomeReturnFailure.disabled }
            try published.validate()
            // Request-start bound expires proofs conservatively, without assuming a network grace period.
            serverOffset = Double(published.serverTimeMillis) / 1000 - policyRequestStartedAt.timeIntervalSince1970
            let value = try await service.account(for: scope)
            guard ticket == generation, gate() else { return }
            try value.validate(for: scope)
            guard minimumAccountVersion.map({ value.version >= $0 }) ?? true else { throw NativeHomeReturnFailure.invalid }
            minimumAccountVersion = max(minimumAccountVersion ?? value.version, value.version)
            policy = published; account = value; requiresAccountReadback = false
            // A successful current read clears only its transient read error, not an original denial.
            failure = decision == nil ? nil : settledFailure
            phase = pending == nil ? .ready : .unknown
        } catch {
            guard ticket == generation, gate() else { return }
            account = nil; policy = nil; failure = (error as? NativeHomeReturnFailure) ?? .network
            phase = pending == nil ? .unavailable : .unknown
        }
    }
    /// Manual sample only. Success stages a proof; it never restores as a side effect.
    public func checkIn(home: PrivateHomeSnapshot?) async {
        guard gate(), !Task.isCancelled, canCheckIn, let service, let policy, let account else { return }
        let ticket = generation
        phase = .checking; failure = nil; settledFailure = nil; decision = nil; noReceiptYet = false; proof = nil; proofAccountVersion = nil
        do {
            let status = await location()
            guard commandIsCurrent(ticket) else { return }
            let usable = challenge.flatMap { $0.homeVersion == home?.version && $0.accountVersion == account.version && $0.policyVersion == policy.policyVersion ? $0.id : nil }
            let check = try NativeHomeReturnCheck.preflight(home: home, status: status, policy: policy, scope: scope, now: now(),
                expectedAccountVersion: native ? account.version : nil, challengeId: usable)
            if native { guard check.fix != nil else { throw NativeHomeReturnFailure.invalid } }
            // The adapter's own check precedes this async resumption. Recheck the
            // current foreground/services/permission before forwarding its measured fix.
            guard locationAuthorized() else { throw NativeHomeReturnFailure.permissionDenied }
            let verification = try await service.verify(check)
            guard commandIsCurrent(ticket) else { return }
            // Verification may already have reached the server. Do not stage a late
            // proof/challenge after local revocation; this does not undo that request.
            guard locationAuthorized() else { throw NativeHomeReturnFailure.permissionDenied }
            do {
                let value = try verification.proof(for: check)
                guard now().addingTimeInterval(serverOffset) < value.expiresAt else { throw NativeHomeReturnFailure.proofExpired }
                proof = value; proofAccountVersion = account.version; challenge = nil; retryAfterSeconds = nil; phase = .verified
            } catch NativeHomeReturnFailure.dwellRequired(let seconds) {
                guard let id = verification.challengeId else { throw NativeHomeReturnFailure.invalid }
                challenge = (id, check.homeVersion, account.version, policy.policyVersion)
                retryAfterSeconds = seconds; failure = .dwellRequired(retryAfterSeconds: seconds); phase = .dwelling
            }
        } catch {
            guard commandIsCurrent(ticket) else { return }
            challenge = nil; retryAfterSeconds = nil; failure = (error as? NativeHomeReturnFailure) ?? .network; phase = .ready
        }
    }
    /// Separate explicit player confirmation, bound to the still-current home/account proof.
    public func confirmRestore(home: PrivateHomeSnapshot?) async {
        guard gate(), !Task.isCancelled else { return }
        guard locationAuthorized() else { cancelVerification(); failure = .permissionDenied; return }
        guard canRestore, home?.status == .active, let proof, let version = proofAccountVersion else { return }
        let ticket = generation
        let request: NativeHomeRestoreRequest
        do {
            request = try NativeHomeRestoreRequest(proof: proof, currentHomeVersion: home?.version ?? -1,
                expectedAccountVersion: version, deviceNow: now(), serverOffset: serverOffset)
            if native { try request.validateNative() }
            try checkJournalScope()
        } catch { failure = (error as? NativeHomeReturnFailure) ?? .invalid; cancelVerification(); return }
        phase = .restoring; savingRequest = request; pauseAfterSettlement = false
        defer { if savingRequest == request { savingRequest = nil } }
        do {
            if let journal { try await journal.save(request) }
            guard commandIsCurrent(ticket) else { return }
            pending = request; self.proof = nil; challenge = nil; proofAccountVersion = nil
            savingRequest = nil
        } catch {
            guard commandIsCurrent(ticket) else { return }
            // A throwing save is not proof that the durable slot stayed empty. Keep the
            // attempted identity, just as cancellation during save does, until an explicit
            // recovery can compare that exact record. Never adopt a replacement or re-save it.
            pending = request; self.proof = nil; challenge = nil; proofAccountVersion = nil
            failure = .storageUnavailable; phase = .unknown; return
        }
        await restore(request)
    }
    public func retryExact() async {
        guard gate(), !Task.isCancelled, canRetryExact, let pending else { return }
        await restore(pending)
    }
    public func readBack() async {
        guard gate(), !Task.isCancelled, phase == .unknown, let service, let request = pending else { return }
        let ticket = generation; phase = .restoring; pauseAfterSettlement = false
        do {
            let receipt = try await service.restoreReceipt(for: request)
            guard commandIsCurrent(ticket) else { return }
            guard let receipt else { noReceiptYet = true; phase = .unknown; return }
            try await settle(receipt, for: request, ticket: ticket)
        } catch {
            guard commandIsCurrent(ticket) else { return }
            failure = .unknown; phase = .unknown; return
        }
        await reloadAfterSettlement(ticket: ticket)
    }
    private func restore(_ request: NativeHomeRestoreRequest) async {
        guard gate(), let service else { return }
        guard !Task.isCancelled else { cancelVerification(); return }
        let ticket = generation; phase = .restoring; noReceiptYet = false; pauseAfterSettlement = false
        do {
            try checkJournalScope()
            if let journal {
                let stored = try await journal.read()
                guard commandIsCurrent(ticket) else { return }
                guard stored == request else { throw NativeHomeReturnFailure.storageUnavailable }
            }
            guard commandIsCurrent(ticket) else { return }
            let receipt = try await service.restore(request)
            guard commandIsCurrent(ticket) else { return }
            try await settle(receipt, for: request, ticket: ticket)
        } catch {
            guard commandIsCurrent(ticket) else { return }
            failure = (error as? NativeHomeReturnFailure) == .storageUnavailable ? .storageUnavailable : .unknown; phase = .unknown; return
        }
        await reloadAfterSettlement(ticket: ticket)
    }
    private func settle(_ receipt: NativeHomeRestoreReceipt, for request: NativeHomeRestoreRequest, ticket: UUID) async throws {
        try receipt.validate(for: request); try checkJournalScope()
        guard commandIsCurrent(ticket) else { return }
        settlingTicket = ticket
        defer { if settlingTicket == ticket { settlingTicket = nil } }
        if let journal { try await journal.clear(matching: request) }
        guard ticket == generation, gate() else { return }
        pending = nil; decision = receipt.decision; settledFailure = receipt.failure; failure = settledFailure; noReceiptYet = false
        minimumAccountVersion = max(minimumAccountVersion ?? receipt.accountVersion, receipt.accountVersion)
        account = nil; requiresAccountReadback = true; phase = .idle
    }
    private func reloadAfterSettlement(ticket: UUID) async {
        guard ticket == generation, gate() else { return }
        if pauseAfterSettlement || Task.isCancelled {
            pauseAfterSettlement = false
            // The original terminal decision is known, but no current balance was read.
            // Existing UI offers an explicit refresh from unavailable; never use receipt balance.
            phase = .unavailable; return
        }
        await load()
    }

}
