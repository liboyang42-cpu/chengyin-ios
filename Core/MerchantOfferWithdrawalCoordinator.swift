import Foundation

/// Session identity for this flow only. Tokens never enter this module; the
/// injected executor owns authenticated transport.
public struct MerchantOfferWithdrawalSession: Equatable, Sendable {
    public let accountID: Int
    public let epoch: UInt64
    public init(accountID: Int, epoch: UInt64) throws {
        guard accountID > 0 else { throw MerchantOfferWithdrawalFailure.invalid("session") }
        self.accountID = accountID; self.epoch = epoch
    }
}

/// Minimal original-intent lock. Keys contain only account and offer IDs —
/// never reasons, tokens or payloads. A lock taken before dispatch is only
/// released by a definitive rejection or by a confirmed readback; an unknown
/// outcome keeps it, so nothing is ever resent automatically.
@MainActor public protocol MerchantOfferWithdrawalIntentLocking: AnyObject {
    func contains(_ key: String) throws -> Bool
    func acquire(_ key: String) throws
    func complete(_ key: String) throws
}

public enum MerchantOfferWithdrawalLockKey {
    public static func make(session: MerchantOfferWithdrawalSession, offerID: Int) -> String {
        "\(session.accountID):offer-withdraw:\(offerID)"
    }
}

@MainActor public final class MerchantOfferWithdrawalMemoryIntentLocks: MerchantOfferWithdrawalIntentLocking {
    private var keys: Set<String> = []
    public init() {}
    public func contains(_ key: String) throws -> Bool { keys.contains(key) }
    public func acquire(_ key: String) throws {
        guard !keys.contains(key) else { throw MerchantOfferWithdrawalFailure.locked }
        keys.insert(key)
    }
    public func complete(_ key: String) throws { keys.remove(key) }
}

@MainActor public final class MerchantOfferWithdrawalFileIntentLocks: MerchantOfferWithdrawalIntentLocking {
    private let url: URL
    public init(url: URL) { self.url = url }
    private func read() throws -> Set<String> {
        if !FileManager.default.fileExists(atPath: url.path) { return [] }
        do { return Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: url))) }
        catch { throw MerchantOfferWithdrawalFailure.storage } // Corruption never means "unlocked".
    }
    private func write(_ keys: Set<String>) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(keys.sorted()).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw MerchantOfferWithdrawalFailure.storage }
    }
    public func contains(_ key: String) throws -> Bool { try read().contains(key) }
    public func acquire(_ key: String) throws {
        var keys = try read()
        guard !keys.contains(key) else { throw MerchantOfferWithdrawalFailure.locked }
        keys.insert(key); try write(keys)
    }
    public func complete(_ key: String) throws { var keys = try read(); keys.remove(key); try write(keys) }
}

/// Execution boundary. The shipped implementation is dormant; a production
/// implementation may only be injected by the integration owner after the
/// shared mutation wiring is approved. `withdraw` must throw
/// `MerchantOfferWithdrawalFailure.rejected` only for a definitive business
/// rejection; transport ambiguity must throw `.unknown`.
@MainActor public protocol MerchantOfferWithdrawalExecuting: AnyObject {
    var permitsSubmission: Bool { get }
    func withdraw(_ request: MerchantOfferWithdrawalRequest, session: MerchantOfferWithdrawalSession) async throws -> MerchantOfferWithdrawalResponseHint
    func mineRows(session: MerchantOfferWithdrawalSession) async throws -> [MerchantContentValue]
}

@MainActor public final class MerchantOfferWithdrawalDormantExecutor: MerchantOfferWithdrawalExecuting {
    public init() {}
    public var permitsSubmission: Bool { false }
    public func withdraw(_ request: MerchantOfferWithdrawalRequest, session: MerchantOfferWithdrawalSession) async throws -> MerchantOfferWithdrawalResponseHint {
        throw MerchantOfferWithdrawalFailure.disabled
    }
    public func mineRows(session: MerchantOfferWithdrawalSession) async throws -> [MerchantContentValue] {
        throw MerchantOfferWithdrawalFailure.disabled
    }
}

public struct MerchantOfferWithdrawalReview: Equatable {
    public let id: UUID
    public let subject: MerchantOfferWithdrawalSubject
    public let request: MerchantOfferWithdrawalRequest
    public let impact: MerchantOfferWithdrawalImpact
    fileprivate let session: MerchantOfferWithdrawalSession
    fileprivate let created: Date
}

@MainActor public final class MerchantOfferWithdrawalCoordinator {
    public enum Phase: Equatable {
        case idle
        case reviewing
        case confirmed(serverReason: String, matchesRequestedReason: Bool, enrollmentPausedHint: Bool?)
        case alreadyWithdrawn(serverReason: String)
        case unknown(readback: MerchantOfferWithdrawalReadback?)
        case rejected(message: String?)
        case ineligible(MerchantOfferWithdrawalIneligibility)
        case disabled, locked, failed(MerchantOfferWithdrawalFailure)
    }

    private let currentSession: () -> MerchantOfferWithdrawalSession?
    private let executor: any MerchantOfferWithdrawalExecuting
    private let locks: any MerchantOfferWithdrawalIntentLocking
    private let now: () -> Date
    public private(set) var phase: Phase = .idle
    public private(set) var review: MerchantOfferWithdrawalReview?
    public private(set) var busy = false
    /// Set when a confirmed readback should make the host reload `mine` and
    /// return. Consumed by the App layer once.
    public private(set) var confirmedOfferID: Int?

    public init(currentSession: @escaping () -> MerchantOfferWithdrawalSession?,
                executor: any MerchantOfferWithdrawalExecuting = MerchantOfferWithdrawalDormantExecutor(),
                locks: any MerchantOfferWithdrawalIntentLocking = MerchantOfferWithdrawalMemoryIntentLocks(),
                now: @escaping () -> Date = Date.init) {
        self.currentSession = currentSession; self.executor = executor; self.locks = locks; self.now = now
    }

    public var permitsSubmission: Bool { executor.permitsSubmission }

    @discardableResult
    public func prepare(subject: MerchantOfferWithdrawalSubject, rawReason: String) -> MerchantOfferWithdrawalReview? {
        guard !busy else { return nil }
        review = nil; confirmedOfferID = nil
        if let ineligibility = subject.ineligibility {
            if case .alreadyWithdrawn(let serverReason) = ineligibility {
                phase = .alreadyWithdrawn(serverReason: serverReason)
            } else { phase = .ineligible(ineligibility) }
            return nil
        }
        guard let session = currentSession() else { phase = .failed(.changedSession); return nil }
        guard let offerID = subject.offerID else { phase = .ineligible(.missingOffer); return nil }
        do {
            let request = try MerchantOfferWithdrawalRequest(offerID: offerID, rawReason: rawReason)
            let key = MerchantOfferWithdrawalLockKey.make(session: session, offerID: offerID)
            if try locks.contains(key) {
                // A prior intent for this exact offer is unresolved. Surface
                // the readback path instead of preparing a second send.
                phase = .unknown(readback: nil); return nil
            }
            let value = MerchantOfferWithdrawalReview(id: UUID(), subject: subject, request: request,
                impact: MerchantOfferWithdrawalImpact(subject: subject), session: session, created: now())
            review = value; phase = .reviewing; return value
        } catch let error as MerchantOfferWithdrawalFailure {
            phase = .failed(error); return nil
        } catch { phase = .failed(.invalid("prepare")); return nil }
    }

    public func cancelReview() {
        guard !busy else { return }
        review = nil; if phase == .reviewing { phase = .idle }
    }

    /// Dispatches at most once for the prepared intent. The intent lock is
    /// acquired before the executor is called; any ambiguity after that
    /// point keeps the lock and moves to `.unknown`, where the only next
    /// step is a precise readback — never an automatic resend.
    public func confirm(_ accepted: MerchantOfferWithdrawalReview) async {
        guard !busy, review == accepted else { return }
        guard executor.permitsSubmission else { phase = .disabled; return }
        guard let session = currentSession(), session == accepted.session else { phase = .failed(.changedSession); return }
        guard now().timeIntervalSince(accepted.created) >= 0, now().timeIntervalSince(accepted.created) <= 300 else {
            review = nil; phase = .failed(.changedSession); return
        }
        busy = true; defer { busy = false }
        review = nil // Consume before suspension: duplicate taps cannot dispatch twice.
        let key = MerchantOfferWithdrawalLockKey.make(session: session, offerID: accepted.request.offerID)
        do { try locks.acquire(key) }
        catch { phase = .locked; return }

        let hint: MerchantOfferWithdrawalResponseHint
        do {
            hint = try await executor.withdraw(accepted.request, session: session)
        } catch let error as MerchantOfferWithdrawalFailure {
            guard currentSession() == session else { phase = .unknown(readback: nil); return }
            switch error {
            case .rejected(_, let message):
                try? locks.complete(key); phase = .rejected(message: message)
            case .disabled:
                try? locks.complete(key); phase = .disabled
            default:
                phase = .unknown(readback: nil) // Lock retained.
            }
            return
        } catch {
            phase = .unknown(readback: nil); return
        }
        // A response from a previous account/epoch is never applied.
        guard !Task.isCancelled, currentSession() == session else { phase = .unknown(readback: nil); return }
        await readback(session: session, offerID: accepted.request.offerID,
                       requestedReason: accepted.request.reason.value,
                       enrollmentPausedHint: hint.enrollmentPaused, key: key)
    }

    /// Read-only recovery for an unknown outcome. Never dispatches.
    public func reconcileUnknown(offerID: Int, requestedReason: String?) async {
        guard !busy, let session = currentSession() else { return }
        if case .confirmed = phase { return }
        busy = true; defer { busy = false }
        let key = MerchantOfferWithdrawalLockKey.make(session: session, offerID: offerID)
        await readback(session: session, offerID: offerID, requestedReason: requestedReason,
                       enrollmentPausedHint: nil, key: key)
    }

    private func readback(session: MerchantOfferWithdrawalSession, offerID: Int, requestedReason: String?,
                          enrollmentPausedHint: Bool?, key: String) async {
        do {
            let rows = try await executor.mineRows(session: session)
            guard !Task.isCancelled, currentSession() == session else { phase = .unknown(readback: nil); return }
            let result = MerchantOfferWithdrawalReadback.verify(offerID: offerID, requestedReason: requestedReason, mineRows: rows)
            switch result {
            case .confirmed(let serverReason, let matches):
                try? locks.complete(key)
                confirmedOfferID = offerID
                // The server reason is authoritative. A differing reason is
                // shown as the server's, never claimed as this submission's.
                phase = .confirmed(serverReason: serverReason, matchesRequestedReason: matches,
                                    enrollmentPausedHint: enrollmentPausedHint)
            default:
                phase = .unknown(readback: result) // Lock retained; no resend.
            }
        } catch {
            guard currentSession() == session else { return }
            phase = .unknown(readback: nil)
        }
    }

    public func consumeConfirmedOfferID() -> Int? {
        defer { confirmedOfferID = nil }
        return confirmedOfferID
    }
}
