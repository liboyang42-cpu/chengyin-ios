import Foundation
import CryptoKit

/// Exclusive AI-draft → authorizer → original review → publish → player-consume path.
/// Reuses `MerchantNPCKnowledgeDraft` / `MerchantNPCHTTPClient`. Does not own order/publish writers.
public enum MerchantNPCDraftOrigin: Equatable { case human, ai }
public enum MerchantNPCDraftPhase: Equatable {
    case idle, aiDraft, authorizerVerified, originalReviewPending, published, waitingSource
}

public enum MerchantNPCDraftGateFailure: Error, Equatable {
    case waitingSource(capability: String)
    case authorizerRequired
    case originalReviewRequired
    case unpublished
    case aiCannotPrice
    case aiCannotDeductStock
    case aiCannotAward
    case aiCannotCertifyPresence
    case aiUnavailable
    case isolationViolation
    case qualificationRevoked
    case invalidDraft
    case staleScope
    public var isWaitingSource: Bool { if case .waitingSource = self { return true }; return false }
    public static func commerce(_ mutation: MerchantNPCForbiddenAICommerce) -> Self {
        switch mutation {
        case .price: return .aiCannotPrice
        case .deductStock: return .aiCannotDeductStock
        case .award: return .aiCannotAward
        case .certifyPresence: return .aiCannotCertifyPresence
        }
    }
    public var messageKey: String {
        switch self {
        case .waitingSource: return "merchantNPC.draft.waitingSource"
        case .authorizerRequired: return "merchantNPC.draft.authorizerRequired"
        case .originalReviewRequired: return "merchantNPC.draft.originalReviewRequired"
        case .unpublished: return "merchantNPC.draft.unpublished"
        case .aiCannotPrice: return "merchantNPC.draft.aiCannotPrice"
        case .aiCannotDeductStock: return "merchantNPC.draft.aiCannotDeductStock"
        case .aiCannotAward: return "merchantNPC.draft.aiCannotAward"
        case .aiCannotCertifyPresence: return "merchantNPC.draft.aiCannotCertifyPresence"
        case .aiUnavailable: return "merchantNPC.draft.aiUnavailable"
        case .isolationViolation: return "merchantNPC.draft.isolationViolation"
        case .qualificationRevoked: return "merchantNPC.draft.qualificationRevoked"
        case .invalidDraft: return "merchantNPC.draft.invalid"
        case .staleScope: return "merchantNPC.draft.staleScope"
        }
    }
}

public struct MerchantNPCAuthorizer: Equatable {
    public let accountID: Int
    public let merchantRowID: PublicMerchantRowID
    public init?(accountID: Int, merchantRowID: PublicMerchantRowID) {
        guard accountID > 0 else { return nil }
        self.accountID = accountID; self.merchantRowID = merchantRowID
    }
    public func matches(_ scope: MerchantNPCScope) -> Bool {
        accountID == scope.accountID && merchantRowID == scope.merchantRowID
    }
}

public struct MerchantNPCOriginalReviewTicket: Equatable {
    public let requestID: UUID
    public let scope: MerchantNPCScope
    public let factsHash: String
    public init(requestID: UUID, scope: MerchantNPCScope, factsHash: String) {
        self.requestID = requestID; self.scope = scope; self.factsHash = factsHash
    }
}

public struct MerchantNPCDraftReadFact: Equatable, Sendable {
    public let requestID: String
    public let state: String
    public init(requestID: String, state: String) {
        self.requestID = requestID
        self.state = state
    }
}

public struct MerchantNPCPublishedRevision: Equatable {
    public let revision: UUID
    public let scope: MerchantNPCScope
    public let facts: Data
    public init(revision: UUID, scope: MerchantNPCScope, facts: Data) {
        self.revision = revision; self.scope = scope; self.facts = facts
    }
}

/// Original knowledge review/publish writer. Default implementation is WAITING_SOURCE, not a successful stub.
public protocol MerchantNPCOriginalReviewPublishing: AnyObject {
    func submitForOriginalReview(_ draft: MerchantNPCKnowledgeDraft, requestID: UUID, scope: MerchantNPCScope) async throws -> MerchantNPCOriginalReviewTicket
    func publishApproved(_ ticket: MerchantNPCOriginalReviewTicket, scope: MerchantNPCScope) async throws -> MerchantNPCPublishedRevision
}

@MainActor public final class MerchantNPCWaitingSourcePublisher: MerchantNPCOriginalReviewPublishing {
    public static let knowledgeDraftHTTP = "MerchantNpcKnowledgeDraftService.http"
    public static let knowledgeReviewAuthority = "MerchantNpcKnowledgeReviewAuthority.route"
    public init() {}
    public func submitForOriginalReview(_ draft: MerchantNPCKnowledgeDraft, requestID: UUID, scope: MerchantNPCScope) async throws -> MerchantNPCOriginalReviewTicket {
        throw MerchantNPCDraftGateFailure.waitingSource(capability: Self.knowledgeReviewAuthority)
    }
    public func publishApproved(_ ticket: MerchantNPCOriginalReviewTicket, scope: MerchantNPCScope) async throws -> MerchantNPCPublishedRevision {
        throw MerchantNPCDraftGateFailure.waitingSource(capability: Self.knowledgeDraftHTTP)
    }
}

enum MerchantNPCDraftDigest {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor public final class MerchantNPCDraftApprovalGate {
    public static let aiThemeDraftRead = "AiThemeDraftRequestService.read"
    public let scope: MerchantNPCScope
    private let currentScope: () -> MerchantNPCScope?
    private let publisher: any MerchantNPCOriginalReviewPublishing
    private let isolation: MerchantNPCPublicPrivateIsolation
    private let qualification: MerchantNPCQualificationRevoke
    public private(set) var phase: MerchantNPCDraftPhase = .idle
    public private(set) var origin: MerchantNPCDraftOrigin?
    public private(set) var draft = MerchantNPCKnowledgeDraft()
    public private(set) var authorizer: MerchantNPCAuthorizer?
    public private(set) var reviewTicket: MerchantNPCOriginalReviewTicket?
    public private(set) var published: MerchantNPCPublishedRevision?
    public private(set) var failure: MerchantNPCDraftGateFailure?
    public init(scope: MerchantNPCScope, publisher: (any MerchantNPCOriginalReviewPublishing)? = nil,
                isolation: MerchantNPCPublicPrivateIsolation = .init(),
                qualification: MerchantNPCQualificationRevoke = .init(),
                currentScope: @escaping () -> MerchantNPCScope?) {
        self.scope = scope; self.publisher = publisher ?? MerchantNPCWaitingSourcePublisher()
        self.isolation = isolation; self.qualification = qualification; self.currentScope = currentScope
    }
    public var isCurrent: Bool { currentScope() == scope && qualification.allowsServing(scope) }
    public var themeMainlineAvailableWhenAIUnavailable: Bool {
        MerchantNPCPublicPrivateIsolation.themeMainlineAvailableWhenAIUnavailable
    }
    public func ingestAIDraft(_ value: MerchantNPCKnowledgeDraft) throws {
        guard isCurrent else { throw fail(.staleScope) }
        guard value.validationIssues.isEmpty, !value.encodesLiveCommerceMutation else { throw fail(.invalidDraft) }
        draft = value; origin = .ai; authorizer = nil; reviewTicket = nil; published = nil
        phase = .aiDraft; failure = nil
        qualification.rememberPrivate(value, scope: scope)
        isolation.retainPrivate(draft: value, scope: scope)
    }
    public func requestAIDraftGeneration() async throws -> Never {
        throw fail(.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeDraftHTTP))
    }
    public func applyAICommerce(_ mutation: MerchantNPCForbiddenAICommerce) throws -> Never {
        _ = draft.applyingAICommerce(mutation)
        throw fail(.commerce(mutation))
    }
    public func noteAIUnavailable() {
        failure = .aiUnavailable
    }
    public func verifyByAuthorizer(_ value: MerchantNPCAuthorizer) throws {
        guard isCurrent else { throw fail(.staleScope) }
        guard phase == .aiDraft || phase == .authorizerVerified, origin == .ai else { throw fail(.unpublished) }
        guard value.matches(scope) else { throw fail(.authorizerRequired) }
        authorizer = value; phase = .authorizerVerified; failure = nil
    }
    public func submitOriginalReview(requestID: UUID) async throws -> MerchantNPCOriginalReviewTicket {
        guard isCurrent else { throw fail(.staleScope) }
        guard phase == .authorizerVerified, authorizer?.matches(scope) == true else { throw fail(.authorizerRequired) }
        do {
            let ticket = try await publisher.submitForOriginalReview(draft, requestID: requestID, scope: scope)
            guard isCurrent else { throw fail(.staleScope) }
            reviewTicket = ticket; phase = .originalReviewPending; failure = nil
            return ticket
        } catch let error as MerchantNPCDraftGateFailure {
            throw record(error)
        } catch {
            throw fail(.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority))
        }
    }
    /// Forward one knowledge-review GET only when the publisher is already that writer.
    /// `MerchantNPCWaitingSourcePublisher` does not send. Does not publish.
    public func recoverKnowledgeReview(_ held: MerchantNPCKnowledgeReviewReentry) async throws -> MerchantNPCKnowledgeReviewReentry {
        guard let writer = publisher as? MerchantNPCKnowledgeReviewWriter else {
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority)
        }
        return try await writer.recoverReentry(held)
    }

    /// One GET from the stored request id. The current scope member must already match.
    /// Does not POST and does not publish.
    public func recoverKnowledgeIdentity(requestID: UUID, memberID: Int64) async throws -> MerchantNPCKnowledgeReviewReentry {
        guard isCurrent, memberID > 0, Int64(scope.accountID) == memberID else { throw fail(.staleScope) }
        guard let writer = publisher as? MerchantNPCKnowledgeReviewWriter else {
            throw MerchantNPCDraftGateFailure.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority)
        }
        return try await writer.recoverIdentity(requestID: requestID, memberID: memberID)
    }
    public func publishApproved() async throws -> MerchantNPCPublishedRevision {
        guard isCurrent else { throw fail(.staleScope) }
        guard authorizer?.matches(scope) == true else { throw fail(.authorizerRequired) }
        guard let ticket = reviewTicket, phase == .originalReviewPending else { throw fail(.originalReviewRequired) }
        do {
            let revision = try await publisher.publishApproved(ticket, scope: scope)
            guard isCurrent else { throw fail(.staleScope) }
            published = revision; phase = .published; failure = nil
            isolation.publish(revision, scope: scope)
            qualification.rememberPublished(revision, scope: scope)
            return revision
        } catch let error as MerchantNPCDraftGateFailure {
            throw record(error)
        } catch {
            throw fail(.waitingSource(capability: MerchantNPCWaitingSourcePublisher.knowledgeDraftHTTP))
        }
    }
    /// Read an existing AI theme draft. Missing closure throws WAITING_SOURCE and does not
    /// change phase, publish state, or private scope. Does not publish or price.
    public func recoverFromDraftRead(
        memberID: Int64?,
        requestID: String?,
        read: ((Int64, String) -> MerchantNPCDraftReadFact?)?
    ) throws -> MerchantNPCDraftReadFact? {
        let trimmed = requestID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let memberID, memberID > 0, !trimmed.isEmpty else { return nil }
        guard let read else {
            throw MerchantNPCDraftGateFailure.waitingSource(capability: Self.aiThemeDraftRead)
        }
        return read(memberID, trimmed)
    }
    public func playerConsume() throws -> Data {
        guard qualification.allowsServing(scope) else { throw fail(.qualificationRevoked) }
        guard isCurrent else { throw fail(.staleScope) }
        guard phase == .published else { throw fail(.unpublished) }
        return try isolation.playerProjection(scope: scope, qualification: qualification)
    }
    @discardableResult private func fail(_ error: MerchantNPCDraftGateFailure) -> MerchantNPCDraftGateFailure {
        failure = error
        if error.isWaitingSource { phase = .waitingSource }
        return error
    }
    private func record(_ error: MerchantNPCDraftGateFailure) -> MerchantNPCDraftGateFailure {
        fail(error)
    }
}
