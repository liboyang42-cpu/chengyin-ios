import Foundation

/// Baseline carries the complete relevant source row/terms and relationship permissions.
/// The provider must actually re-read source endpoints; cached role labels are insufficient.
public struct CoopFlowEvidence: Equatable {
    public let baseline: CoopFlowJSON
    public let permitted: Bool
    public init(baseline: CoopFlowJSON, permitted: Bool) { self.baseline = baseline; self.permitted = permitted }
}
@MainActor public protocol CoopFlowEvidenceReading: AnyObject {
    func freshEvidence(for operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowEvidence
}
@MainActor public protocol CoopFlowExecuting: AnyObject {
    var dispatchScope: String? { get }
    func permitsDispatch(_ operation: CoopFlowMutation) -> Bool
    func execute(_ operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowJSON
}
public extension CoopFlowExecuting {
    /// Legacy custom executors remain source-compatible; protected dispatch requires a scope.
    var dispatchScope: String? { nil }
}
@MainActor public final class CoopFlowDormantExecutor: CoopFlowExecuting {
    private let service: CoopFlowService
    public init(service: CoopFlowService) { self.service = service }
    public var dispatchScope: String? { service.dispatchScope }
    public func permitsDispatch(_ operation: CoopFlowMutation) -> Bool { service.permitsDispatch(operation) }
    public func execute(_ operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowJSON {
        try await service.perform(operation, session: session)
    }
}
/// An atomic, on-disk lock is committed before network dispatch. No credentials, reasons or financial values are persisted.
@MainActor public protocol CoopFlowLockStore: AnyObject {
    func contains(_ key: String) throws -> Bool
    func acquire(_ key: String) throws
    func complete(_ key: String) throws
}
@MainActor public final class CoopFlowFileLocks: CoopFlowLockStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    private func read() throws -> Set<String> {
        if !FileManager.default.fileExists(atPath: url.path) { return [] }
        do { return Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: url))) }
        catch { throw CoopFlowFailure.storage } // Corruption never means “unlocked”.
    }
    private func write(_ keys: Set<String>) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(keys.sorted()).write(to: url, options: [.atomic])
        } catch { throw CoopFlowFailure.storage }
    }
    public func contains(_ key: String) throws -> Bool { try read().contains(key) }
    public func acquire(_ key: String) throws {
        var keys = try read(); guard !keys.contains(key) else { throw CoopFlowFailure.ambiguous }
        keys.insert(key); try write(keys)
    }
    public func complete(_ key: String) throws { var keys = try read(); keys.remove(key); try write(keys) }
}
public struct CoopFlowReview: Equatable {
    public let id: UUID
    public let operation: CoopFlowMutation
    public let accountID: Int
    public let epoch: UInt64
    public let baseline: CoopFlowJSON
    public let requestBody: CoopFlowJSON
    fileprivate let dispatchScope: String?
    fileprivate let created: Date
    fileprivate let capturedSession: CoopFlowSession
    fileprivate init(operation: CoopFlowMutation, session: CoopFlowSession, baseline: CoopFlowJSON, dispatchScope: String?, now: Date) throws {
        self.dispatchScope = dispatchScope
        capturedSession = session
        id = UUID(); self.operation = operation; accountID = session.accountID; epoch = session.epoch
        self.baseline = baseline; requestBody = try operation.body(); created = now
    }
}
@MainActor public final class CoopFlowCoordinator {
    private let current: () -> CoopFlowSession?
    private let evidence: any CoopFlowEvidenceReading
    private let executor: any CoopFlowExecuting
    private let locks: any CoopFlowLockStore
    private let now: () -> Date
    private var review: CoopFlowReview?
    private var busy = false
    /// Closed by default. Tests may inject fake adapters and opt in. Shipping composition must keep false.
    private let enabled: Bool
    public init(current: @escaping () -> CoopFlowSession?, evidence: any CoopFlowEvidenceReading,
                executor: any CoopFlowExecuting, locks: any CoopFlowLockStore, enabled: Bool = false,
                now: @escaping () -> Date = Date.init) {
        self.current = current; self.evidence = evidence; self.executor = executor; self.locks = locks
        self.enabled = enabled; self.now = now
    }
    public func invalidate() { review = nil }
    public func prepare(_ operation: CoopFlowMutation) async throws -> CoopFlowReview {
        guard !busy else { throw CoopFlowFailure.conflict }; busy = true; defer { busy = false }
        review = nil
        guard let session = current() else { throw APIError.unauthorized }
        _ = try operation.body()
        let scope = executor.dispatchScope
        let fresh = try await evidence.freshEvidence(for: operation, session: session)
        try Task.checkCancellation(); guard current() == session else { throw CoopFlowFailure.stale }
        guard executor.dispatchScope == scope else { throw CoopFlowFailure.stale }
        try validate(operation, fresh: fresh, session: session)
        guard try !hasLock(operation, account: session.accountID, scope: scope) else { throw CoopFlowFailure.ambiguous }
        let value = try CoopFlowReview(operation: operation, session: session, baseline: fresh.baseline, dispatchScope: scope, now: now())
        review = value; return value
    }
    public func confirm(_ accepted: CoopFlowReview) async throws -> CoopFlowJSON {
        guard enabled, executor.permitsDispatch(accepted.operation) else { throw CoopFlowFailure.disabled }
        guard !accepted.operation.requiresSeparateEnablement || accepted.dispatchScope != nil else { throw CoopFlowFailure.disabled }
        guard !busy else { throw CoopFlowFailure.conflict }; busy = true; defer { busy = false }
        guard executor.dispatchScope == accepted.dispatchScope, review == accepted, let session = current(), session == accepted.capturedSession, session.accountID == accepted.accountID,
              session.epoch == accepted.epoch, now().timeIntervalSince(accepted.created) >= 0,
              now().timeIntervalSince(accepted.created) <= 120 else { throw CoopFlowFailure.stale }
        // Consume before suspension: duplicate taps cannot dispatch twice.
        review = nil
        let fresh = try await evidence.freshEvidence(for: accepted.operation, session: session)
        try Task.checkCancellation(); guard current() == session else { throw CoopFlowFailure.stale }
        try validate(accepted.operation, fresh: fresh, session: session)
        guard executor.dispatchScope == accepted.dispatchScope else { throw CoopFlowFailure.stale }
        guard fresh.baseline == accepted.baseline else { throw CoopFlowFailure.conflict }
        guard try !hasLock(accepted.operation, account: session.accountID, scope: accepted.dispatchScope) else { throw CoopFlowFailure.ambiguous }
        let key = scopedLockKey(accepted.operation, account: session.accountID, scope: accepted.dispatchScope)
        try locks.acquire(key)
        // Any throw after acquire (timeout/cancel/malformed/server rejection/account switch) remains locked.
        // No retry or automatic reconciliation can infer a financial outcome.
        let result = try await executor.execute(accepted.operation, session: session)
        try Task.checkCancellation(); guard current() == session else { throw CoopFlowFailure.stale }
        guard executor.dispatchScope == accepted.dispatchScope else { throw CoopFlowFailure.stale }
        try locks.complete(key)
        return result
    }
    private func validate(_ op: CoopFlowMutation, fresh: CoopFlowEvidence, session: CoopFlowSession) throws {
        guard fresh.permitted else { throw CoopFlowFailure.permission }
        switch op {
        case .review(_, let member, _, _): guard member != session.accountID else { throw CoopFlowFailure.permission }
        case .invite(let form):
            if form.kind == .merchant && form.recipient.id == session.accountID { throw CoopFlowFailure.permission }
        case .handle(_, let action, let reason):
            let row = fresh.baseline["invite"] == .null ? fresh.baseline : fresh.baseline["invite"]
            let state = CoopFlowContractState(invite: row)
            let isFrom = row["fromId"].integer == session.accountID
            // toId club space is not memberId. Evidence must establish club authority separately.
            let isTo = fresh.permitted && !isFrom
            guard state.actions(isFrom: isFrom, isTo: isTo).contains(action) else { throw CoopFlowFailure.permission }
            if action == .cancel, row["status"].integer == 1,
               reason?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { throw CoopFlowFailure.invalid("reason") }
        default: break
        }
    }
    private func scopedLockKey(_ op: CoopFlowMutation, account: Int, scope: String?) -> String {
        let legacy = lockKey(op, account: account)
        guard let scope else { return legacy }
        // Scope contains only the immutable approved base URL, never credentials or payloads.
        return "endpoint:" + Data(scope.utf8).base64EncodedString() + ":" + legacy
    }
    private func hasLock(_ op: CoopFlowMutation, account: Int, scope: String?) throws -> Bool {
        // Honor pre-upgrade unknown locks. An epoch change never releases either key.
        if try locks.contains(lockKey(op, account: account)) { return true }
        return try locks.contains(scopedLockKey(op, account: account, scope: scope))
    }
    private func lockKey(_ op: CoopFlowMutation, account: Int) -> String {
        let resource: String
        switch op {
        case .invite(let f): resource = "invite-new-\(f.topicID)-\(f.kind.rawValue)-\(f.recipient.id)"
        case .handle(let id, _, _), .contact(let id), .attachPerks(let id, _): resource = "invite-\(id)"
        case .apply(let id), .withdraw(let id): resource = "pool-topic-\(id)"
        case .decline(let id, _): resource = "application-\(id)"
        case .confirm(let id), .reject(let id): resource = "registration-\(id)"
        case .createTemplate: resource = "template-create"
        case .deleteTemplate(let id): resource = "template-\(id)"
        case .enrollOffer(let fields): resource = "offer-chapter-\(fields["chapterId"]?.integer ?? 0)"
        case .reconfirmOffer(let id), .pauseOffer(let id): resource = "offer-\(id)"
        case .review(let topic, let member, _, _): resource = "review-\(topic)-\(member)"
        case .complaint(let id, _): resource = "complaint-\(id)"
        }
        return "\(account):\(resource)"
    }
}
