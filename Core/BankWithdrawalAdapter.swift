import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Dormant by default. There is no production factory or live grant in this migration.
/// Tests inject synthetic transport only. The backend, not the client, decides withdrawability.
@MainActor public final class BankWithdrawalAdapter {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let journal: any OperationPendingJournal
    private let approval: OperationEndpointApproval?
    private let enableReviewedWrites: Bool
    private let currentSession: () -> BankWithdrawalSession?
    private let consentEvidence: () -> BankWithdrawalConsentEvidence?
    private let now: () -> Date
    private var reviewed: BankWithdrawalReview?
    private var proof: BankWithdrawalProof?
    private var capturedSession: BankWithdrawalSession?
    private var record: OperationPendingRecord?
    private var busy = false
    private let target = "bank-withdrawal"
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                journal: any OperationPendingJournal, approval: OperationEndpointApproval? = nil,
                enableReviewedWrites: Bool = false,
                consentEvidence: @escaping () -> BankWithdrawalConsentEvidence? = { nil },
                currentSession: @escaping () -> BankWithdrawalSession?, now: @escaping () -> Date = Date.init) {
        self.configuration = configuration; self.transport = transport; self.journal = journal
        self.approval = approval; self.enableReviewedWrites = enableReviewedWrites
        self.consentEvidence = consentEvidence; self.currentSession = currentSession; self.now = now
    }
    public var scope: WalletCommerceScope? { currentSession()?.scope }
    public var isAvailable: Bool { enableReviewedWrites && approval != nil }
    public var hasUnresolvedOutcome: Bool {
        guard let scope else { return false }
        do { return try journal.pending(ownerKey: owner(scope), targetKey: target) != nil }
        catch { return true }
    }
    private func owner(_ scope: WalletCommerceScope) -> String { "bank:\(scope.namespace.utf8.count):\(scope.namespace):\(scope.accountID)" }
    public func review(_ draft: BankWithdrawalDraft) throws -> BankWithdrawalReview {
        guard !busy else { throw BankWithdrawalFailure.busy }
        _ = try draft.validatedAmount()
        guard let session = currentSession(), session.scope.valid, AuthRequestBuilder.isValidToken(session.token) else { throw APIError.unauthorized }
        guard try journal.pending(ownerKey: owner(session.scope), targetKey: target) == nil else { throw BankWithdrawalFailure.unresolved }
        let value = BankWithdrawalReview(id: UUID(), scope: session.scope, draft: draft, created: now())
        reviewed = value; proof = nil; capturedSession = session; return value
    }
    /// Local form cancellation never initiates a request. In-flight/unknown locks remain durable.
    public func discardLocalInput() { reviewed = nil; proof = nil; capturedSession = nil }
    private func requireSession(_ review: BankWithdrawalReview) throws -> BankWithdrawalSession {
        guard let session = currentSession(), session == capturedSession, session.scope == review.scope else { throw BankWithdrawalFailure.staleSession }
        return session
    }
    private func requireConsent(_ scope: WalletCommerceScope) throws {
        guard let consent = consentEvidence(), consent.scope == scope, consent.valid else { throw BankWithdrawalFailure.consentRequired }
    }
    private func authorizedRequest(path: String, body: [String: Any], review: BankWithdrawalReview) throws -> URLRequest {
        guard enableReviewedWrites else { throw BankWithdrawalFailure.unavailable }
        let session = try requireSession(review)
        try requireConsent(session.scope)
        guard approval?.allows(configuration: configuration, namespace: session.scope.namespace,
                               accountID: session.scope.accountID, path: path) == true else { throw BankWithdrawalFailure.unavailable }
        return try OperationAdapterHTTP.json(configuration: configuration, path: path,
                    body: JSONSerialization.data(withJSONObject: body), token: session.token)
    }
    private func validateEnvelope(_ data: Data, status: Int) throws {
        guard status != 401, status != 403 else { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw BankWithdrawalFailure.unresolved }
        struct Envelope: Decodable { let code: Int; let businessCode: String? }
        let value = try JSONDecoder().decode(Envelope.self, from: data)
        guard value.code != 401, value.code != 403 else { throw APIError.unauthorized }
        guard value.code == 200 else {
            // Only recognized machine codes are exposed. Do not echo arbitrary PII-bearing messages.
            let safe = ["WITHDRAWAL_CONSENT_REQUIRED", "LOGIN_REQUIRED", "PREFLIGHT_EXPIRED", "PREFLIGHT_REJECTED", "PREFLIGHT_CONSUMED", "PREFLIGHT_BINDING_MISMATCH", "PREFLIGHT_INTENT_CONFLICT", "PREFLIGHT_INTENT_CLOSED", "PREFLIGHT_NOT_FOUND", "PREFLIGHT_INPUT_INVALID", "PREFLIGHT_STATE_CHANGED"]
            throw BankWithdrawalFailure.rejected(safe.contains(value.businessCode ?? "") ? value.businessCode! : "REQUEST_REJECTED")
        }
    }
    private func send(_ request: URLRequest, review: BankWithdrawalReview) async throws -> Data {
        _ = try requireSession(review); try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation(); _ = try requireSession(review)
        try validateEnvelope(data, status: status); return data
    }
    private func challenge(_ data: Data) throws -> BankWithdrawalChallenge {
        struct Envelope: Decodable { let data: BankWithdrawalChallenge }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }
    private func persistStep(_ step: Int) throws {
        guard var next = record else { throw BankWithdrawalFailure.unresolved }
        next.acknowledgedSteps = step; try journal.write(next); record = next
    }
    public func prepare(_ review: BankWithdrawalReview) async throws -> BankWithdrawalProof {
        guard !busy else { throw BankWithdrawalFailure.busy }
        guard reviewed == review, now().timeIntervalSince(review.created) >= 0,
              now().timeIntervalSince(review.created) < 120 else { throw BankWithdrawalFailure.reviewRequired }
        let request = try authorizedRequest(path: "api/fund/preflight/bank-withdrawal",
                          body: review.draft.fields(requestID: review.id.uuidString), review: review)
        guard try journal.pending(ownerKey: owner(review.scope), targetKey: target) == nil else { throw BankWithdrawalFailure.unresolved }
        try Task.checkCancellation()
        let pending = OperationPendingRecord(operationID: review.id, ownerKey: owner(review.scope), targetKey: target)
        try journal.write(pending) // Metadata only, durably recorded before any possible dispatch.
        record = pending; busy = true
        defer { busy = false }
        let started = now()
        let data = try await send(request, review: review)
        guard reviewed == review else { throw BankWithdrawalFailure.reviewRequired }
        let response = try challenge(data); try response.validate(review: review)
        // Use request-start time conservatively so network latency cannot extend a challenge.
        let value = try BankWithdrawalProof(response: response, review: review, expiresAt: response.expiry(receivedAt: started))
        guard now() < value.expiresAt else { throw BankWithdrawalFailure.expired }
        try persistStep(1); proof = value; return value
    }
    private func requireProof(_ value: BankWithdrawalProof) throws {
        guard proof == value, reviewed == value.review else { throw BankWithdrawalFailure.reviewRequired }
        _ = try requireSession(value.review)
        guard now() >= value.review.created, now() < value.expiresAt else { throw BankWithdrawalFailure.expired }
        guard let record, try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record else { throw BankWithdrawalFailure.unresolved }
    }
    public func submit(_ value: BankWithdrawalProof) async throws -> BankWithdrawalReceipt {
        guard !busy else { throw BankWithdrawalFailure.busy }
        try requireProof(value)
        // Validate BOTH grants before confirming; approval of confirmation alone cannot spend.
        let confirm = try authorizedRequest(path: "api/fund/preflight/\(value.challengeID)/confirm",
                        body: ["challengeToken": value.token], review: value.review)
        let create = try authorizedRequest(path: "api/withdrawal/create",
                       body: value.review.draft.fields(requestID: value.review.id.uuidString, challengeID: value.challengeID), review: value.review)
        busy = true; proof = nil; defer { busy = false }
        let confirmed = try challenge(await send(confirm, review: value.review))
        try confirmed.validate(review: value.review)
        guard confirmed.challengeId == value.challengeID, confirmed.state == "CONFIRMED", confirmed.canProceed,
              confirmed.riskLevel != "BLOCKED" else { throw BankWithdrawalFailure.malformed }
        try persistStep(2)
        guard reviewed == value.review else { throw BankWithdrawalFailure.reviewRequired }
        _ = try requireSession(value.review)
        guard now() < value.expiresAt else { throw BankWithdrawalFailure.expired }
        try requireConsent(value.review.scope)
        // Proof becomes single-use before create; ambiguous outcomes cannot be retried.
        proof = nil
        let data = try await send(create, review: value.review)
        struct Receipt: Decodable { let data: Int }
        let id = try JSONDecoder().decode(Receipt.self, from: data).data
        guard id > 0 else { throw BankWithdrawalFailure.malformed }
        guard let record else { throw BankWithdrawalFailure.unresolved }
        try journal.clear(record); self.record = nil; discardLocalInput()
        return BankWithdrawalReceipt(applicationID: id)
    }
    /// Explicit user rejection only. No background reject, automatic retry, or automatic payout.
    public func reject(_ value: BankWithdrawalProof) async throws {
        guard !busy else { throw BankWithdrawalFailure.busy }
        try requireProof(value)
        let request = try authorizedRequest(path: "api/fund/preflight/\(value.challengeID)/reject",
                        body: ["challengeToken": value.token], review: value.review)
        busy = true; proof = nil; defer { busy = false }
        let response = try challenge(await send(request, review: value.review))
        try response.validate(review: value.review)
        guard response.challengeId == value.challengeID, response.state == "REJECTED", let record else { throw BankWithdrawalFailure.malformed }
        try journal.clear(record); self.record = nil; discardLocalInput()
    }
    // No recovery reset and no automatic create replay. The list has no reliable requestId lookup.
}
