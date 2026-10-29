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
    /// Theme-draft request id this author flow already has. Never minted here.
    public private(set) var heldThemeDraftMemberID: Int64?
    public private(set) var heldThemeDraftRequestID: String?
    /// Accepted knowledge-review request. Outlives one editor state. Not a theme-draft id.
    public private(set) var heldKnowledgeReview: MerchantNPCKnowledgeReviewReentry?

    /// Nil keeps the accepted request in memory only. The store is the disk identity, not a second writer.
    public let recovery: MerchantNPCKnowledgeRecoveryStore?

    public init(scope: MerchantNPCScope, publisher: (any MerchantNPCOriginalReviewPublishing)? = nil,
                isolation: MerchantNPCPublicPrivateIsolation = .init(),
                qualification: MerchantNPCQualificationRevoke = .init(),
                currentScope: @escaping () -> MerchantNPCScope?,
                recovery: MerchantNPCKnowledgeRecoveryStore? = nil) {
        self.recovery = recovery
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
    /// The one request id passed in is stored on this flow. A ticket that carries a different id is not stored.
    /// The member id is the one already on that author request. This does not mint another id.
    public func submitForOriginalReview(requestID: UUID) async throws -> MerchantNPCOriginalReviewTicket {
        do {
            let ticket = try await gate.submitOriginalReview(requestID: requestID)
            retainAcceptedKnowledgeReview(requestID: requestID, ticket: ticket)
            retainSubmittedAuthorRequest(requestID, memberID: Int64(ticket.scope.accountID), returned: ticket.requestID)
            return ticket
        } catch let error as MerchantNPCDraftGateFailure {
            if case .waitingSource(let capability) = error,
               capability == Self.missingReviewCapability || capability == Self.missingPublishCapability {
                stayedOnMissingPublisher = true
                retainSubmittedAuthorRequest(requestID, memberID: Int64(gate.scope.accountID), returned: requestID)
            }
            throw error
        }
    }

    /// Re-enter the editor's stored knowledge-review request. Does not read a theme-draft id and does not publish.
    public func recoverKnowledgeReview(_ held: MerchantNPCKnowledgeReviewReentry) async throws -> MerchantNPCKnowledgeReviewReentry {
        try await gate.recoverKnowledgeReview(held)
    }

    /// One GET for a request id already stored beside the character save. Does not POST or publish.
    public func recoverKnowledgeRequest(_ requestID: UUID) async throws -> MerchantNPCKnowledgeReviewReentry? {
        let memberID = Int64(gate.scope.accountID)
        guard memberID > 0 else { return nil }
        let kept = try await gate.recoverKnowledgeIdentity(requestID: requestID, memberID: memberID)
        guard kept.requestID == requestID, kept.memberID == memberID else { return nil }
        heldKnowledgeReview = kept
        return kept
    }

    /// A different request id on the accept record is read once. The current member and merchant must match.
    /// A missing row stays closed and is not deleted. This does not POST or publish.
    public func recoverStoredKnowledgeReview() async throws -> MerchantNPCKnowledgeReviewReentry? {
        let stored = recovery?.read()
        let storedMatches = stored?.memberID == Int64(gate.scope.accountID)
            && stored?.merchantRowID == gate.scope.merchantRowID.rawValue
            && stored?.ownerKey == recovery?.ownerKey
        if let heldKnowledgeReview, !storedMatches || stored?.requestID == heldKnowledgeReview.requestID {
            return heldKnowledgeReview
        }
        guard let stored, storedMatches else { return heldKnowledgeReview }
        let kept = try await gate.recoverKnowledgeIdentity(requestID: stored.requestID, memberID: stored.memberID)
        guard kept.requestID == stored.requestID, kept.memberID == stored.memberID else { return heldKnowledgeReview }
        heldKnowledgeReview = kept
        return kept
    }

    /// Store the accepted re-entry from the ticket member and the four strings supply already kept.
    /// A different request id is not stored. Missing authored strings are not invented.
    private func retainAcceptedKnowledgeReview(requestID: UUID, ticket: MerchantNPCOriginalReviewTicket) {
        guard ticket.requestID == requestID, let authored else { return }
        heldKnowledgeReview = MerchantNPCKnowledgeReviewReentry(
            requestID: requestID,
            memberID: Int64(ticket.scope.accountID),
            name: authored.name.value,
            greeting: authored.greeting.value,
            persona: authored.persona.value,
            knowledge: authored.knowledge.value)
        guard let recovery,
              ticket.scope.merchantRowID.rawValue == recovery.merchantRowID,
              Int64(ticket.scope.accountID) > 0 else { return }
        do {
            try recovery.saveAccepted(requestID: requestID, memberID: Int64(ticket.scope.accountID))
        } catch {
            // The accepted ticket stays on this flow. A disk failure does not become a second submit.
        }
    }

    /// Keep the request id this submit already received. A different returned id is refused and does not replace a held id.
    /// Does not mint an id, does not read the network, and does not publish.
    private func retainSubmittedAuthorRequest(_ submitted: UUID, memberID: Int64, returned: UUID) {
        guard returned == submitted else { return }
        _ = holdThemeDraftRequest(memberID: memberID, requestID: submitted.uuidString)
    }

    /// Remember a request id the author already has. An invalid id is refused and does not replace a held id.
    /// Does not read the network, does not mint an id, and does not publish.
    @discardableResult
    public func holdThemeDraftRequest(memberID: Int64, requestID: String) -> Bool {
        let trimmed = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard memberID > 0, Self.isThemeDraftRequestID(trimmed) else { return false }
        heldThemeDraftMemberID = memberID
        heldThemeDraftRequestID = trimmed
        return true
    }

    /// UUID shape the server accepts before it will read a theme draft request. This does not create one.
    public static func isThemeDraftRequestID(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        let lengths = [8, 4, 4, 4, 12]
        guard parts.count == lengths.count else { return false }
        for (part, length) in zip(parts, lengths) {
            guard part.count == length, part.allSatisfy(\.isHexDigit) else { return false }
        }
        return true
    }

    /// Read an existing draft fact. Does not publish.
    /// A fact whose request id differs from the one asked for is not a hit and does not change phase.
    public func recoverFromDraftRead(memberID: Int64?, requestID: String?,
                                     read: ((Int64, String) -> MerchantNPCDraftReadFact?)?) throws -> MerchantNPCDraftReadFact? {
        let phaseBeforeRead = gate.phase
        let fact = try gate.recoverFromDraftRead(memberID: memberID, requestID: requestID, read: read)
        let expected = requestID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let fact, fact.requestID != expected {
            guard gate.phase == phaseBeforeRead else { return nil }
            return nil
        }
        return fact
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
