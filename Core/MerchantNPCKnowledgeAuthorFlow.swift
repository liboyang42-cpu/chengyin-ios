import Foundation

/// Merchant NPC knowledge authoring. The author supplies name, greeting, persona, and
/// knowledge through `MerchantNPCFieldDraft`, then this entry wraps
/// `MerchantNPCDraftApprovalGate` for AI ingest, scope-matched verify, original review,
/// draft read, and player consume.
///
/// A missing publisher stays on `knowledgeReviewAuthority` / `knowledgeDraftHTTP`.
/// This type does not publish, does not post a theme draft, and does not mint a policy version.
/// Field text that fails the catalog control-character or length rule stays on the authored
/// character and is not truncated into public facts. No product price is created.
@MainActor public final class MerchantNPCKnowledgeAuthorFlow {
    public struct AuthoredFields: Equatable {
        public let name: MerchantNPCFieldDraft
        public let greeting: MerchantNPCFieldDraft
        public let persona: MerchantNPCFieldDraft
        public let knowledge: MerchantNPCFieldDraft
        public let character: MerchantStoreCharacter
    }

    public static let missingReviewCapability = MerchantNPCWaitingSourcePublisher.knowledgeReviewAuthority
    public static let missingPublishCapability = MerchantNPCWaitingSourcePublisher.knowledgeDraftHTTP

    public let gate: MerchantNPCDraftApprovalGate
    public private(set) var authored: AuthoredFields?
    /// Set when original review cannot leave the missing publisher capabilities. Publish is not attempted.
    public private(set) var stayedOnMissingPublisher = false

    public init(scope: MerchantNPCScope, publisher: (any MerchantNPCOriginalReviewPublishing)? = nil,
                isolation: MerchantNPCPublicPrivateIsolation = .init(),
                qualification: MerchantNPCQualificationRevoke = .init(),
                currentScope: @escaping () -> MerchantNPCScope?) {
        gate = MerchantNPCDraftApprovalGate(
            scope: scope, publisher: publisher, isolation: isolation, qualification: qualification, currentScope: currentScope
        )
    }

    /// Apply the four existing field drafts onto one character. Does not ingest or publish.
    @discardableResult
    public func supply(name: MerchantNPCFieldDraft, greeting: MerchantNPCFieldDraft,
                       persona: MerchantNPCFieldDraft, knowledge: MerchantNPCFieldDraft,
                       source: MerchantOperationsDraft) throws -> AuthoredFields {
        guard name.field == .name, greeting.field == .greeting, persona.field == .persona, knowledge.field == .knowledge else {
            throw MerchantNPCDraftGateFailure.invalidDraft
        }
        let drafts = [name, greeting, persona, knowledge]
        guard drafts.allSatisfy({ $0.issueKey == nil }) else { throw MerchantNPCDraftGateFailure.invalidDraft }
        var current = source
        for draft in drafts {
            do { current = try draft.applying(to: current) }
            catch { throw MerchantNPCDraftGateFailure.invalidDraft }
        }
        guard case .character(let character) = current else { throw MerchantNPCDraftGateFailure.invalidDraft }
        let authored = AuthoredFields(name: name, greeting: greeting, persona: persona, knowledge: knowledge, character: character)
        self.authored = authored
        return authored
    }

    /// Ingest the authored character as an AI draft. Catalog rows are display FAQ only.
    public func ingestAsAIDraft() throws {
        guard let authored else { throw MerchantNPCDraftGateFailure.invalidDraft }
        let catalog = Self.catalog(from: authored.character)
        guard catalog.validationIssues.isEmpty, catalog.encodesLiveCommerceMutation == false else {
            throw MerchantNPCDraftGateFailure.invalidDraft
        }
        try gate.ingestAIDraft(catalog)
    }

    /// An authorizer that matches the gate scope can verify. A mismatch does not promote the draft.
    public func verify(_ authorizer: MerchantNPCAuthorizer) throws {
        try gate.verifyByAuthorizer(authorizer)
    }

    /// Submit for original review. A missing publisher stays on the review/draft capabilities and does not publish.
    public func submitForOriginalReview(requestID: UUID) async throws -> MerchantNPCOriginalReviewTicket {
        do {
            return try await gate.submitOriginalReview(requestID: requestID)
        } catch let error as MerchantNPCDraftGateFailure {
            if case .waitingSource(let capability) = error,
               capability == Self.missingReviewCapability || capability == Self.missingPublishCapability {
                stayedOnMissingPublisher = true
            }
            throw error
        }
    }

    /// Read an existing draft fact. Does not publish and does not change phase.
    public func recoverFromDraftRead(memberID: Int64?, requestID: String?,
                                     read: ((Int64, String) -> MerchantNPCDraftReadFact?)?) throws -> MerchantNPCDraftReadFact? {
        try gate.recoverFromDraftRead(memberID: memberID, requestID: requestID, read: read)
    }

    /// Closed until a real publish has moved the gate to `.published`.
    public func playerConsume() throws -> Data {
        try gate.playerConsume()
    }

    /// Copy only field values the structured catalog can store whole. Never a prefix, a price, or a live mutation.
    private static func catalog(from character: MerchantStoreCharacter) -> MerchantNPCKnowledgeDraft {
        var draft = MerchantNPCKnowledgeDraft()
        let source = MerchantOperationsDraft.character(character)
        for field in MerchantNPCTextField.allCases {
            guard let value = field.value(in: source), MerchantNPCKnowledgeDraft.validText(value, max: 600) else { continue }
            draft.faq.append(.init(question: field.rawValue, answer: value))
        }
        return draft
    }
}
