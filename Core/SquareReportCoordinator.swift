import Foundation

@MainActor public protocol SquareReportAccess {
    var identity: SquareGovernanceIdentity? { get }
    var token: String? { get }
    func freshSubject(_ target: SocialActionTarget) async throws -> SocialActionSnapshot
}

@MainActor public final class SquareReportCoordinator {
    public let service: SquareReportService
    private let journal: SquareGovernanceJournal
    private let caseStore: SquareReportCaseStore
    private var inFlight = false
    private var consumed = Set<UUID>()
    private var receipts: [String: SquareReportReceipt] = [:]
    public init(service: SquareReportService, journal: SquareGovernanceJournal? = nil, caseStore: SquareReportCaseStore? = nil) {
        self.service = service; self.journal = journal ?? .persistent()
        self.caseStore = caseStore ?? (service.synthetic ? .ephemeral() : .persistent())
    }
    private func check(_ identity: SquareGovernanceIdentity, access: any SquareReportAccess) throws {
        try Task.checkCancellation()
        guard identity.valid, identity == access.identity, let token = access.token, AuthRequestBuilder.isValidToken(token) else { throw SquareReportFailure.signedOut }
    }
    private func receiptKey(target: SquareReportTarget, identity: SquareGovernanceIdentity) -> String {
        "\(identity.namespace.utf8.count):\(identity.namespace):\(identity.accountID):\(target.lockKey)"
    }
    public func isLocked(target: SquareReportTarget, identity: SquareGovernanceIdentity) -> Bool { journal.contains(target.lockKey, identity: identity) }
    public func receipt(target: SquareReportTarget, identity: SquareGovernanceIdentity) -> SquareReportReceipt? {
        receipts[receiptKey(target: target, identity: identity)]
    }
    public func load(target: SquareReportTarget, access: any SquareReportAccess) async throws -> SquareReportSnapshot {
        try await load(target: target, refreshingTarget: false, access: access)
    }
    /// A fresh editing snapshot may adopt an authoritative newer version of the
    /// same qualified subject. Confirmation always uses the strict load above.
    public func reload(target: SquareReportTarget, access: any SquareReportAccess) async throws -> SquareReportSnapshot {
        try await load(target: target, refreshingTarget: true, access: access)
    }
    private func load(target: SquareReportTarget, refreshingTarget: Bool, access: any SquareReportAccess) async throws -> SquareReportSnapshot {
        guard service.readsEnabled else { throw SquareReportFailure.disabled }
        guard let identity = access.identity, let token = access.token else { throw SquareReportFailure.signedOut }
        try check(identity, access: access)
        let policy = try await service.policy(token: token) { try self.check(identity, access: access) }
        let subject = try await access.freshSubject(target.source)
        try check(identity, access: access)
        let current: SquareReportTarget
        if refreshingTarget {
            guard let post = subject.post else { throw SquareReportFailure.invalid }
            current = try .init(post: post, comment: subject.comment)
            guard current.source == target.source else { throw SquareReportFailure.invalid }
        } else { current = target }
        return try .init(identity: identity, target: current, policy: policy, subject: subject)
    }
    public func prepare(snapshot: SquareReportSnapshot, reasonCode: String, description: String,
                        access: any SquareReportAccess, now: Date = Date()) throws -> SquareReportReview {
        guard !inFlight else { throw SquareReportFailure.busy }
        try check(snapshot.identity, access: access)
        guard !isLocked(target: snapshot.target, identity: snapshot.identity) else { throw SquareReportFailure.locked }
        guard (0...300).contains(now.timeIntervalSince(snapshot.observedAt)) else { throw SquareReportFailure.stale }
        return try .init(snapshot: snapshot, reasonCode: reasonCode, description: description, now: now)
    }
    public func confirm(_ review: SquareReportReview, access: any SquareReportAccess, now: Date = Date()) async throws -> SquareReportReceipt {
        guard service.writesEnabled else { throw SquareReportFailure.disabled }
        guard !inFlight else { throw SquareReportFailure.busy }
        guard !consumed.contains(review.id), !isLocked(target: review.snapshot.target, identity: review.snapshot.identity) else { throw SquareReportFailure.locked }
        guard (0...300).contains(now.timeIntervalSince(review.createdAt)) else { throw SquareReportFailure.stale }
        inFlight = true; defer { inFlight = false }
        try check(review.snapshot.identity, access: access)
        let fresh = try await load(target: review.snapshot.target, access: access)
        guard fresh.sameContext(as: review.snapshot) else { throw SquareReportFailure.stale }
        guard let token = access.token else { throw SquareReportFailure.signedOut }
        // Persist before dispatch. A new screen, account epoch or app process must
        // not create another request ID after an unconfirmed write.
        guard journal.claim(fresh.target.lockKey, identity: fresh.identity) else { throw SquareReportFailure.locked }
        consumed.insert(review.id)
        let result = try await service.submit(review, token: token) { try self.check(fresh.identity, access: access) }
        receipts[receiptKey(target: fresh.target, identity: fresh.identity)] = result
        caseStore.record(result.id, target: fresh.target, identity: fresh.identity)
        return result
    }
    public func recover(target: SquareReportTarget, expectedIdentity: SquareGovernanceIdentity,
                        access: any SquareReportAccess) async throws -> SquareReportReceipt? {
        try check(expectedIdentity, access: access)
        guard let id = try caseStore.reference(target: target, identity: expectedIdentity), let token = access.token else { return nil }
        let result = try await service.receipt(id: id, token: token) { try self.check(expectedIdentity, access: access) }
        guard result.id == id, result.targetType == target.type, result.targetID == target.id else { throw SquareReportFailure.malformed }
        receipts[receiptKey(target: target, identity: expectedIdentity)] = result
        return result
    }
    public func refresh(_ receipt: SquareReportReceipt, target: SquareReportTarget, expectedIdentity: SquareGovernanceIdentity,
                        access: any SquareReportAccess) async throws -> SquareReportReceipt {
        try check(expectedIdentity, access: access)
        guard receipt.targetType == target.type, receipt.targetID == target.id, let token = access.token else { throw SquareReportFailure.invalid }
        let value = try await service.receipt(id: receipt.id, token: token) { try self.check(expectedIdentity, access: access) }
        guard value.id == receipt.id, value.targetType == receipt.targetType, value.targetID == receipt.targetID,
              value.reasonCode == receipt.reasonCode, value.policyVersion == receipt.policyVersion,
              value.description == receipt.description else { throw SquareReportFailure.malformed }
        receipts[receiptKey(target: target, identity: expectedIdentity)] = value
        // Readback never removes the dispatch lock, even when the case is decided.
        return value
    }
}
