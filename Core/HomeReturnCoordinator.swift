import Foundation
import Observation

/// Reform plan v9 §28 / W19.1, W19.4–W19.6: the player resource account a return-home
/// restore refills. current/max/version are server facts; the client never computes a
/// maximum or a restore amount. Scope is explicit (global or one run/theme).
public struct HomeResourceAccount: Decodable, Equatable, Sendable {
    public let resourceType: String
    public let scopeType: String
    public let scopeId: String?
    public let current, maximum: Int64
    public let version: Int64
    public func validate(for scope: HomeResourceScope) throws {
        var wire = ["scopeType": scopeType, "resourceType": resourceType]
        if let scopeId { wire["scopeId"] = scopeId }
        guard wire == scope.wire, current >= 0, maximum > 0, current <= maximum, ReformWire.version(version) else { throw HomeReturnFailure.invalid }
    }
}

/// Server decision for VerifyReturnHome. Only VERIFIED carries a short-lived proof.
public struct HomeReturnVerification: Decodable, Equatable, Sendable {
    public enum Decision: String, Decodable, Sendable {
        case verified = "VERIFIED", outOfRadius = "OUT_OF_RADIUS", lowAccuracy = "LOW_ACCURACY", staleFix = "STALE_FIX"
        case cooldown = "COOLDOWN", homeChanged = "HOME_CHANGED", noHome = "NO_HOME"
    }
    public let requestId: String
    public let decision: Decision
    public let proofId: String?
    public let homeVersion: Int64
    public let expiresAtMillis: Int64?
    public let retryAfterSeconds: Int?
    /// Maps to a proof or a distinct, understandable failure; never a fake success.
    public func proof(for check: HomeReturnCheck) throws -> HomeReturnProof {
        guard requestId == check.requestId, ReformWire.version(homeVersion) else { throw HomeReturnFailure.invalid }
        switch decision {
        case .verified:
            guard let proofId, let expiresAtMillis, retryAfterSeconds == nil else { throw HomeReturnFailure.invalid }
            return try HomeReturnProof(proofId: proofId, homeVersion: homeVersion, scope: check.scope, expiresAtMillis: expiresAtMillis, for: check)
        case .cooldown:
            guard proofId == nil, let retryAfterSeconds, retryAfterSeconds > 0 else { throw HomeReturnFailure.invalid }
            throw HomeReturnFailure.cooldown(retryAfterSeconds: retryAfterSeconds)
        default:
            guard proofId == nil, retryAfterSeconds == nil else { throw HomeReturnFailure.invalid }
            switch decision {
            case .outOfRadius: throw HomeReturnFailure.outOfRadius
            case .lowAccuracy: throw HomeReturnFailure.lowAccuracy
            case .staleFix: throw HomeReturnFailure.staleFix
            case .homeChanged: throw HomeReturnFailure.homeChanged
            default: throw HomeReturnFailure.noHome
            }
        }
    }
}

/// Transport-free seam for the proposed W19 operations (GetHomeReturnPolicy,
/// GetResourceAccount, VerifyReturnHome, RestoreHomeResources, receipt readback).
/// None is a reviewed endpoint; only DEBUG fixtures conform.
@MainActor public protocol HomeReturnServing: AnyObject {
    /// nil means the server publishes no policy: the feature is unavailable.
    func policy() async throws -> HomeReturnPolicy?
    func account(for scope: HomeResourceScope) async throws -> HomeResourceAccount
    func verify(_ check: HomeReturnCheck) async throws -> HomeReturnVerification
    func restore(_ request: HomeRestoreRequest) async throws -> HomeRestoreReceipt
    func restoreReceipt(for request: HomeRestoreRequest) async throws -> HomeRestoreReceipt?
}

/// Manual "I'm back" flow. Location state is consumed from an injected provider and
/// never sampled in the background; the home point is never shown, logged or exported.
@available(macOS 14.0, *)
@MainActor @Observable public final class HomeReturnCoordinator {
    public enum Phase: String, Sendable { case disabled, idle, loading, ready, unavailable, checking, restoring, unknown, invalidated }
    public private(set) var phase: Phase = .idle
    public private(set) var account: HomeResourceAccount?
    public private(set) var failure: HomeReturnFailure?
    public private(set) var decision: HomeRestoreReceipt.Decision?
    public private(set) var noReceiptYet = false
    public let scope: HomeResourceScope
    private var policy: HomeReturnPolicy?
    private var pending: HomeRestoreRequest?
    private let service: (any HomeReturnServing)?
    private let location: () async -> HomeReturnLocationStatus
    private let isCurrent: () -> Bool
    private let now: () -> Date
    private let serverOffset: () -> TimeInterval
    private var generation = UUID()

    public init(scope: HomeResourceScope, service: (any HomeReturnServing)?, capabilities: ReformWorldCapabilities,
                location: @escaping () async -> HomeReturnLocationStatus, isCurrent: @escaping () -> Bool,
                now: @escaping () -> Date = { Date() }, serverOffset: @escaping () -> TimeInterval = { 0 }) {
        self.scope = scope; self.service = service; self.location = location; self.isCurrent = isCurrent
        self.now = now; self.serverOffset = serverOffset
        if service == nil || !capabilities.allows(.homeReturnRestore) || (try? scope.validate()) == nil { phase = .disabled }
    }

    public var isBusy: Bool { [.loading, .checking, .restoring].contains(phase) }
    public var canCheckIn: Bool { phase == .ready && policy != nil && account != nil && pending == nil && isCurrent() }
    public var canRetryExact: Bool { phase == .unknown && pending != nil && isCurrent() }

    public func invalidate() {
        generation = UUID(); account = nil; policy = nil; pending = nil; failure = nil; decision = nil; noReceiptYet = false
        phase = .invalidated
    }

    private func gate() -> Bool {
        guard phase != .disabled, phase != .invalidated else { return false }
        guard isCurrent() else { invalidate(); return false }
        return true
    }

    public func load() async {
        guard gate(), let service, !isBusy else { return }
        let ticket = generation
        phase = .loading
        do {
            let published = try await service.policy()
            guard ticket == generation, gate() else { return }
            guard let published else { policy = nil; account = nil; phase = pending == nil ? .unavailable : .unknown; return }
            try published.validate()
            let value = try await service.account(for: scope)
            guard ticket == generation, gate() else { return }
            try value.validate(for: scope)
            policy = published; account = value
            phase = pending == nil ? .ready : .unknown
        } catch {
            guard ticket == generation, gate() else { return }
            account = nil; phase = pending == nil ? .unavailable : .unknown
        }
    }

    /// The single explicit player action. `home` is the owner's current private-home read.
    public func checkIn(home: PrivateHomeSnapshot?) async {
        guard gate(), canCheckIn, let service, let policy, let account else { return }
        let ticket = generation
        phase = .checking; failure = nil; decision = nil; noReceiptYet = false
        let request: HomeRestoreRequest
        do {
            let status = await location()
            guard ticket == generation, gate() else { return }
            let check = try HomeReturnCheck.preflight(home: home, status: status, policy: policy, scope: scope, now: now())
            let verification = try await service.verify(check)
            guard ticket == generation, gate() else { return }
            let proof = try verification.proof(for: check)
            request = try HomeRestoreRequest(proof: proof, currentHomeVersion: home?.version ?? -1, expectedAccountVersion: account.version,
                                             deviceNow: now(), serverOffset: serverOffset())
        } catch {
            guard ticket == generation, gate() else { return }
            failure = (error as? HomeReturnFailure) ?? .network; phase = .ready; return
        }
        pending = request
        await restore(request)
    }

    public func retryExact() async {
        guard gate(), canRetryExact, let pending else { return }
        await restore(pending)
    }

    public func readBack() async {
        guard gate(), phase == .unknown, let service, let request = pending else { return }
        let ticket = generation
        phase = .restoring
        do {
            let receipt = try await service.restoreReceipt(for: request)
            guard ticket == generation, gate() else { return }
            guard let receipt else { noReceiptYet = true; phase = .unknown; return }
            try settle(receipt, for: request)
        } catch {
            guard ticket == generation, gate() else { return }
            failure = .unknown; phase = .unknown; return
        }
        await load()
    }

    private func restore(_ request: HomeRestoreRequest) async {
        guard let service else { return }
        let ticket = generation
        phase = .restoring; noReceiptYet = false
        do {
            let receipt = try await service.restore(request)
            guard ticket == generation, gate() else { return }
            try settle(receipt, for: request)
        } catch {
            guard ticket == generation, gate() else { return }
            failure = .unknown; phase = .unknown; return
        }
        await load()
    }

    private func settle(_ receipt: HomeRestoreReceipt, for request: HomeRestoreRequest) throws {
        try receipt.validate(for: request)
        pending = nil; decision = receipt.decision; failure = receipt.failure; noReceiptYet = false
        phase = .idle
    }
}
