import Foundation

/// An opaque player-presented city-node code. Never persisted, logged, copied or treated as a URL.
public struct CityNodeRedemptionCode: Equatable {
    private let value: String
    public init(_ raw: String) throws {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.utf8.count <= 16_384 else { throw MerchantBusinessFailure.invalid }
        value = code
    }
    public var request: MerchantBusinessRequest { .form("api/verify/citynode/redeem", ["code": value]) }
    public static func acceptsPledgeRedeem(_ path: String) -> Bool { false }
    fileprivate var correlationTarget: CityNodeRedemptionTarget? { .init(code: value) }
}

/// Immutable, one-use consent. Neither raw payload nor session credential is public/Codable.
public struct CityNodeRedemptionReview: Equatable, Identifiable {
    public let id: UUID
    public let merchantID: Int
    fileprivate let code: CityNodeRedemptionCode
    fileprivate let session: MerchantBusinessSession
}

/// No production mutation transport exists in MerchantBusinessService's default initializer.
/// Tests may inject its synthetic-only transport. Opening this page never starts camera or network.
@MainActor public final class CityNodeRedemptionCoordinator {
    public enum PendingScope: Equatable { case target, legacy, storage }
    private let service: MerchantBusinessService?
    private let journal: any MerchantBusinessIntentStore
    private let currentSession: () -> MerchantBusinessSession?
    private let unauthorized: (MerchantBusinessSession) -> Void
    private var generation: UInt64 = 0
    public private(set) var review: CityNodeRedemptionReview?
    public private(set) var result: CityNodeRedemptionResult?
    public private(set) var failure: String?
    public private(set) var pendingScope: PendingScope?
    public private(set) var busy = false
    public var isAvailable: Bool { service?.canExecuteVerificationMutation == true }
    public var scope: MerchantBusinessScope? {
        guard let service, let session = currentSession() else { return nil }
        return .init(realm: service.realm, accountID: session.accountID, epoch: session.epoch)
    }
    public init(service: MerchantBusinessService?, journal: any MerchantBusinessIntentStore,
                currentSession: @escaping () -> MerchantBusinessSession?,
                onUnauthorized: @escaping (MerchantBusinessSession) -> Void = { _ in }) {
        self.service = service; self.journal = journal; self.currentSession = currentSession; unauthorized = onUnauthorized
    }
    /// The normal view supplies its frozen reader scope/authorization fence. Defaults keep
    /// direct synthetic callers source-compatible; the production transport remains independent.
    public func prepare(_ raw: String, isCurrent: () -> Bool = { true }) async {
        guard !busy, review == nil else { return }
        result = nil; failure = nil; pendingScope = nil
        let ticket = generation
        var capturedSession: MerchantBusinessSession?
        do {
            let code = try CityNodeRedemptionCode(raw)
            guard let service, service.canExecuteVerificationMutation else { throw MerchantBusinessFailure.disabled }
            guard service.canExecuteSyntheticMutation || journal.isDurable else { throw MerchantBusinessFailure.journal }
            guard isCurrent() else { throw MerchantBusinessFailure.stale }
            guard let session = currentSession() else { throw APIError.unauthorized }
            capturedSession = session
            busy = true; defer { busy = false }
            let access = try await service.access(token: session.token)
            try access.require(["merchant:verify"])
            guard generation == ticket, currentSession() == session, isCurrent(), !Task.isCancelled else { return }
            let candidate = CityNodeRedemptionReview(id: UUID(), merchantID: access.merchantID, code: code, session: session)
            let target = intent(candidate, realm: service.realm)
            try requireNoPending(target)
            guard generation == ticket, currentSession() == session, isCurrent(), !Task.isCancelled else { return }
            review = candidate
        } catch {
            guard generation == ticket, isCurrent(), !Task.isCancelled,
                  capturedSession == nil || currentSession() == capturedSession else { return }
            if error as? MerchantBusinessFailure == .journal { pendingScope = .storage }
            failure = errorKey(error)
            if error as? APIError == .unauthorized, let capturedSession { unauthorized(capturedSession) }
        }
    }
    public func cancelReview() { review = nil; failure = nil }
    public func next() { guard !busy else { return }; review = nil; result = nil; failure = nil; pendingScope = nil; restoreLocalPending() }
    /// Read-only restoration. A legacy record or unreadable storage blocks all new targets.
    /// Scoped records are checked against the next code; no raw payload is stored or restored.
    public func restoreLocalPending() {
        guard !busy, review == nil, let service, let session = currentSession() else { return }
        do {
            let legacyPending = try journal.intents().contains(where: { $0.realm == service.realm && $0.accountID == session.accountID && $0.target == "redemption" })
            guard currentSession() == session else { return }
            if legacyPending {
                pendingScope = .legacy; failure = "merchant.cityRedeem.pending"
            }
        } catch { pendingScope = .storage; failure = "merchant.cityRedeem.pending" }
    }
    /// Close, scene background and account/region changes invalidate any consent and late UI work.
    /// A submitted operation is NEVER unlocked by this local lifecycle event.
    public func invalidate() { generation &+= 1; review = nil; result = nil; failure = nil; pendingScope = nil }
    public func confirm(_ reviewID: UUID, isCurrent: () -> Bool = { true }) async {
        guard !busy, let frozen = review, frozen.id == reviewID else { return }
        review = nil; result = nil; failure = nil; pendingScope = nil
        guard let service, service.canExecuteVerificationMutation else { failure = "merchant.cityRedeem.disabled"; return }
        guard currentSession() == frozen.session, isCurrent() else { failure = "merchant.cityRedeem.stale"; return }
        busy = true; defer { busy = false }
        let ticket = generation
        var reserved: MerchantBusinessIntent?
        var enteredTransport = false
        var dispatchStartedAt: TimeInterval?
        do {
            guard service.canExecuteSyntheticMutation || journal.isDurable else { throw MerchantBusinessFailure.journal }
            // Re-read authoritative permission and merchant identity after the separate confirmation.
            let access = try await service.access(token: frozen.session.token)
            try access.require(["merchant:verify"])
            guard currentSession() == frozen.session, generation == ticket, isCurrent(), !Task.isCancelled,
                  access.merchantID == frozen.merchantID else { throw MerchantBusinessFailure.stale }
            let target = intent(frozen, realm: service.realm)
            // Re-check after fresh VERIFY: another coordinator may have reserved while it awaited access.
            try requireNoPending(target)
            try journal.reserve(target); reserved = target
            // Even an injected journal can re-enter lifecycle/session state. Do not dispatch then.
            guard try journal.intents().contains(target) else { throw MerchantBusinessFailure.journal }
            guard currentSession() == frozen.session, generation == ticket, isCurrent(), !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            enteredTransport = true
            dispatchStartedAt = ProcessInfo.processInfo.systemUptime
            let body = try await service.verificationEnvelope(frozen.code.request, token: frozen.session.token)
            guard responseIsTimely(dispatchStartedAt) else { throw MerchantBusinessFailure.unknown }
            let value = try CityNodeRedemptionResult(body: body, target: frozen.code.correlationTarget)
            // Late responses cannot clear a lock or disclose data to a changed session/page.
            guard currentSession() == frozen.session, generation == ticket, isCurrent(), !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            if value.isUnknown {
                pendingScope = pendingKind(target)
            } else {
                // Local deletion failure cannot turn a verified receipt into an unverified one.
                // Retain the lock/banner and never turn that failure into another POST.
                do { try journal.complete(target); reserved = nil }
                catch { pendingScope = pendingKind(target); failure = "merchant.cityRedeem.pending" }
            }
            guard currentSession() == frozen.session, generation == ticket, isCurrent(), !Task.isCancelled else { return }
            result = value
            if body["code"]?.integer == 401 { unauthorized(frozen.session) }
        } catch {
            // Any transport/malformed/cancelled/late result after reservation remains uncertain.
            // No timer, Next, rescan, dismiss, restart or new login removes an unknown target.
            guard generation == ticket, currentSession() == frozen.session, isCurrent(), !Task.isCancelled else { return }
            if let target = reserved {
                if enteredTransport, responseIsTimely(dispatchStartedAt), let rejected = CityNodeRedemptionResult.transportRejection(error) {
                    do { try journal.complete(target) }
                    catch { pendingScope = pendingKind(target); failure = "merchant.cityRedeem.pending" }
                    guard generation == ticket, currentSession() == frozen.session, isCurrent(), !Task.isCancelled else { return }
                    result = rejected
                } else {
                    pendingScope = pendingKind(target); result = .unknown()
                }
            } else {
                if error as? MerchantBusinessFailure == .journal { pendingScope = .storage }
                failure = errorKey(error)
            }
            if error as? APIError == .unauthorized { unauthorized(frozen.session) }
        }
    }
    /// Explicit original-result read only. A new scan, absence or failed receipt is never a replay permission.
    public func recover(_ raw: String, reader: CityNodeRedemptionReceiptReader? = nil,
                        isCurrent: () -> Bool = { true }) async {
        guard !busy, review == nil, let reader, reader.isCurrent, let service,
              let session = currentSession(), isCurrent() else { return }
        let ticket = generation; busy = true; result = nil; failure = nil
        defer { busy = false }
        do {
            let code = try CityNodeRedemptionCode(raw)
            guard let correlation = code.correlationTarget else { throw MerchantBusinessFailure.pending }
            let access = try await service.access(token: session.token)
            try access.require(["merchant:verify"])
            guard generation == ticket, currentSession() == session, isCurrent(), !Task.isCancelled else { return }
            let records = try journal.intents()
            guard !records.contains(where: { $0.realm == service.realm && $0.accountID == session.accountID && $0.target == "redemption" }) else {
                pendingScope = .legacy; failure = "merchant.cityRedeem.pending"; return
            }
            let pending = records.filter { $0.realm == service.realm && $0.accountID == session.accountID && $0.target == correlation.journalTarget }
            guard !pending.isEmpty, pending.allSatisfy({ $0.merchantID == access.merchantID }) else {
                failure = "merchant.cityRedeem.pending"; return
            }
            let value = try await reader.read(raw, session: session, merchantID: access.merchantID, realm: service.realm)
            guard generation == ticket, currentSession() == session, isCurrent(), reader.isCurrent, !Task.isCancelled else { return }
            guard value.redeemed else { result = .unknown(serverMessage: value.unverifiedServerMessage); pendingScope = .target; return }
            // Only the exact original terminal fact settles records captured before this read.
            result = value
            for record in pending { try journal.complete(record) }
            guard generation == ticket, currentSession() == session, isCurrent(), !Task.isCancelled else { return }
            result = value; pendingScope = nil
        } catch {
            guard generation == ticket, currentSession() == session, isCurrent(), !Task.isCancelled else { return }
            if result?.redeemed != true { result = .unknown() }
            pendingScope = .target; failure = "merchant.cityRedeem.pending"
            if error as? APIError == .unauthorized { unauthorized(session) }
        }
    }
    private func intent(_ review: CityNodeRedemptionReview, realm: String) -> MerchantBusinessIntent {
        let scope = MerchantBusinessScope(realm: realm, accountID: review.session.accountID, epoch: review.session.epoch)
        // Unparseable legacy payloads keep the old coarse safety lock; never guess a target.
        // This UUID is local metadata only, never sent as an invented server receipt key.
        return .init(scope: scope, merchantID: review.merchantID, target: review.code.correlationTarget?.journalTarget ?? "redemption", requestID: "local-" + review.id.uuidString)
    }
    private func requireNoPending(_ target: MerchantBusinessIntent) throws {
        if let pending = try journal.intents().first(where: { CityNodeRedemptionTarget.blocks($0, candidate: target) }) {
            pendingScope = pendingKind(pending); throw MerchantBusinessFailure.pending
        }
    }
    private func pendingKind(_ intent: MerchantBusinessIntent) -> PendingScope {
        intent.target == "redemption" ? .legacy : .target
    }
    private func responseIsTimely(_ startedAt: TimeInterval?) -> Bool {
        guard let startedAt else { return false }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        // Match the original 15-second outcome window, using monotonic time rather than wall time.
        // The existing transport timeout is unchanged. A late response never discharges UNKNOWN.
        return elapsed >= 0 && elapsed < 15
    }
    private func errorKey(_ error: Error) -> String {
        if error as? APIError == .unauthorized { return "merchant.cityRedeem.signIn" }
        switch error as? MerchantBusinessFailure {
        case .disabled: return "merchant.cityRedeem.disabled"
        case .invalid: return "merchant.cityRedeem.invalid"
        case .pending, .journal: return "merchant.cityRedeem.pending"
        case .stale: return "merchant.cityRedeem.stale"
        case .denied: return "merchant.cityRedeem.denied"
        default: return "merchant.cityRedeem.accessFailed"
        }
    }
}
