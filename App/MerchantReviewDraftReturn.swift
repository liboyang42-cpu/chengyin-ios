import SwiftUI
import CryptoKit

/// Only the pre-dispatch public reply/report review can return to its local editor.
/// This object never creates a mutation, request ID, reservation or network call.
@MainActor final class MerchantReviewDraftReturn: ObservableObject {
    struct Source {
        let ownerID: ObjectIdentifier
        let scope: MerchantBusinessScope
        let authorization: UUID?
        let access: MerchantBusinessAccess
        let query: MerchantBusinessQuery
        let payload: Data
        let row: MerchantBusinessRecord
        @MainActor func matches(_ owner: MerchantBusinessViewModel) -> Bool {
            let c = owner.coordinator
            guard ObjectIdentifier(owner) == ownerID, c.isCurrent, !c.isBusy, !c.isLocked, c.receipt == nil, c.failureKey == nil,
                  let currentScope = c.reader.scope, c.reader.isConfigured,
                  scope.accountID == currentScope.accountID, scope.epoch == currentScope.epoch,
                  scope.realm.utf8.elementsEqual(currentScope.realm.utf8), c.reader.authorizationGeneration == authorization,
                  let snapshot = c.snapshot, snapshot.document.query == query,
                  Self.fingerprint(snapshot.document.payload) == payload,
                  snapshot.access == access, snapshot.access.role.utf8.elementsEqual(access.role.utf8),
                  snapshot.access.name.map({ Data($0.utf8) }) == access.name.map({ Data($0.utf8) }),
                  Set(snapshot.access.permissions.map { Data($0.utf8) }) == Set(access.permissions.map { Data($0.utf8) }) else { return false }
            return true
        }
        static func fingerprint(_ value: MerchantBusinessValue) -> Data? {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard let bytes = try? encoder.encode(value) else { return nil }
            return Data(SHA256.hash(data: bytes))
        }
    }
    struct Capture {
        let generation: UUID
        let reviewID: UUID
        let ownerRevision: Int
        let source: Source
        let action: MerchantReviewReplyAction
        let content: String
    }
    struct Return: Identifiable {
        let id = UUID()
        let generation: UUID
        let reviewID: UUID
        let ownerRevision: Int
        let source: Source
        let context: MerchantBusinessEditorContext
        let content: String
    }
    private weak var owner: MerchantBusinessViewModel?
    private var active = false
    @Published private(set) var generation = UUID()
    private var pending: Return?
    private var queued: Return?
    private var resumed: Return?
    private var retiredReviewID: UUID?
    var resumedEditorID: UUID? { resumed?.context.id }
    init(owner: MerchantBusinessViewModel) { self.owner = owner }
    func activate() { guard !active else { return }; active = true; discard() }
    @discardableResult func retire() -> UUID? {
        active = false; retiredReviewID = owner?.coordinator.confirmation?.id
        return discard()
    }
    @discardableResult func discard() -> UUID? {
        let editorID = resumedEditorID
        generation = UUID(); pending = nil; queued = nil; resumed = nil
        return editorID
    }
    func capture(_ review: MerchantBusinessConfirmation) -> Capture? {
        guard active, review.id != retiredReviewID, let owner, owner.coordinator.confirmation?.id == review.id,
              case .review(let id, let version, let action, let content) = review.mutation, action != .delete,
              case .reviews = review.baseline.document.query,
              let row = review.baseline.document.rows.first(where: { $0.kind == .review && $0.id == String(id.rawValue) && $0.fields["version"]?.integer == version }),
              let payload = Source.fingerprint(review.baseline.document.payload) else { return nil }
        let source = Source(ownerID: ObjectIdentifier(owner), scope: review.scope, authorization: review.authorizationGeneration,
                            access: review.baseline.access, query: review.baseline.document.query, payload: payload, row: row)
        guard source.matches(owner), currentMutationMatches(reviewID: review.id, action: action, content: content, row: row) else { return nil }
        do { try review.mutation.validate(in: review.baseline.document, access: review.baseline.access, roles: review.baseline.roles) }
        catch { return nil }
        return .init(generation: generation, reviewID: review.id, ownerRevision: owner.revision, source: source, action: action, content: content)
    }
    @discardableResult func requestReturn(_ capture: Capture) -> Bool {
        guard active, capture.generation == generation, let owner, owner.revision == capture.ownerRevision,
              capture.source.matches(owner), currentMutationMatches(reviewID: capture.reviewID, action: capture.action,
                                                                   content: capture.content, row: capture.source.row) else { return false }
        // Synchronously revoke the frozen confirmation before any editor can reappear.
        owner.cancel(); discard()
        pending = .init(generation: generation, reviewID: capture.reviewID, ownerRevision: owner.revision,
                        source: capture.source, context: .init(kind: .review(capture.source.row, capture.action)), content: capture.content)
        return true
    }
    func didDismiss(reviewID: UUID) -> Return? {
        guard let pending, pending.reviewID == reviewID else { return nil }
        guard current(pending) else { discard(); return nil }
        self.pending = nil; queued = pending
        return pending
    }
    func resume(_ ticket: Return, editorIsVacant: Bool = true) -> MerchantBusinessEditorContext? {
        guard queued?.id == ticket.id else { return nil }
        guard editorIsVacant, current(ticket) else { discard(); return nil }
        queued = nil; resumed = ticket
        return ticket.context
    }
    func initialContent(for editorID: UUID) -> String? {
        guard let resumed, resumed.context.id == editorID, current(resumed) else { return nil }
        return resumed.content // Exact raw bytes, before the existing request normalizer.
    }
    @discardableResult func synchronize() -> UUID? {
        if let value = pending ?? queued ?? resumed, !current(value) { return discard() }
        return nil
    }
    func beginConfirmation(id: UUID) -> Bool {
        guard active, let owner, owner.coordinator.confirmation?.id == id else { return false }
        retiredReviewID = id; discard()
        return true
    }
    func cancelReview(id: UUID) {
        guard let owner, owner.coordinator.confirmation?.id == id else { return }
        discard(); owner.cancel()
    }
    private func current(_ ticket: Return) -> Bool {
        guard active, ticket.generation == generation, let owner, owner.revision == ticket.ownerRevision,
              owner.coordinator.confirmation == nil, ticket.source.matches(owner) else { return false }
        return true
    }
    private func currentMutationMatches(reviewID: UUID, action: MerchantReviewReplyAction, content: String, row: MerchantBusinessRecord) -> Bool {
        guard let current = owner?.coordinator.confirmation, current.id == reviewID,
              case .review(let id, let version, let nextAction, let nextContent) = current.mutation else { return false }
        return String(id.rawValue) == row.id && version == row.fields["version"]?.integer && nextAction == action
            && nextContent.utf8.elementsEqual(content.utf8)
    }
}

/// Returns an unsubmitted aftercare opinion to local editing. No storage or transport work.
@MainActor final class MerchantAftercareDraftReturn: ObservableObject {
    struct Capture {
        let generation: UUID
        let review: MerchantBusinessConfirmation
        let ownerRevision: Int
        let source: MerchantReviewDraftReturn.Source
        let draft: MerchantAftercareEvidenceDraft
    }
    struct Return: Identifiable {
        let id = UUID()
        let generation: UUID
        let reviewID: UUID
        let ownerRevision: Int
        let source: MerchantReviewDraftReturn.Source
        let context: MerchantBusinessEditorContext
        let draft: MerchantAftercareEvidenceDraft
    }
    static func editorBinding(_ source: Binding<MerchantBusinessEditorContext?>, presentedID: UUID?) -> Binding<MerchantBusinessEditorContext?> {
        Binding(get: { source.wrappedValue?.id == presentedID ? source.wrappedValue : nil }, set: { value in
            guard source.wrappedValue?.id == presentedID else { return }; source.wrappedValue = value
        })
    }
    static func ownsDismissal(presentedID: UUID?, currentEditorID: UUID?, pendingEditorID: UUID?) -> Bool {
        presentedID != nil && currentEditorID == nil && pendingEditorID == presentedID
    }
    private weak var owner: MerchantBusinessViewModel?
    private var visible = false
    private var active = false
    @Published private(set) var generation = UUID()
    private var pending: Return?
    private var queued: Return?
    private var resumed: Return?
    private var retiredReviewID: UUID?
    var resumedEditorID: UUID? { resumed?.context.id }
    init(owner: MerchantBusinessViewModel) { self.owner = owner }
    func appear(active: Bool) { visible = true; self.active = active; discard() }
    @discardableResult func disappear() -> UUID? { visible = false; active = false; return retire() }
    @discardableResult func sceneChanged(active: Bool) -> UUID? {
        self.active = visible && active
        return retire()
    }
    @discardableResult func retire() -> UUID? {
        retiredReviewID = owner?.coordinator.confirmation?.id
        return discard()
    }
    @discardableResult func discard() -> UUID? {
        let id = resumedEditorID; generation = UUID(); pending = nil; queued = nil; resumed = nil; return id
    }
    func capture(_ review: MerchantBusinessConfirmation) -> Capture? {
        guard visible, active, review.id != retiredReviewID, let owner,
              owner.coordinator.confirmation?.id == review.id,
              case .aftercare(let id, let decision, let content, let evidence) = review.mutation,
              review.baseline.document.query == .refund(id),
              let row = review.baseline.document.rows.first(where: { $0.kind == .refund && $0.id == String(id.rawValue) }),
              let bytes = MerchantReviewDraftReturn.Source.fingerprint(review.baseline.document.payload) else { return nil }
        let source = MerchantReviewDraftReturn.Source(ownerID: ObjectIdentifier(owner), scope: review.scope,
            authorization: review.authorizationGeneration, access: review.baseline.access,
            query: review.baseline.document.query, payload: bytes, row: row)
        guard source.matches(owner), matches(review) else { return nil }
        do { try review.mutation.validate(in: review.baseline.document, access: review.baseline.access, roles: review.baseline.roles) }
        catch { return nil }
        return .init(generation: generation, review: review, ownerRevision: owner.revision, source: source,
            draft: .init(decision: decision, content: content, evidence: evidence ?? ""))
    }
    @discardableResult func requestReturn(_ capture: Capture) -> Bool {
        guard visible, active, capture.generation == generation, let owner,
              owner.revision == capture.ownerRevision, capture.source.matches(owner), matches(capture.review) else { return false }
        owner.cancel(); discard()
        pending = .init(generation: generation, reviewID: capture.review.id, ownerRevision: owner.revision,
            source: capture.source, context: .init(kind: .aftercare(capture.source.row)), draft: capture.draft)
        return true
    }
    func didDismiss(reviewID: UUID) -> Return? {
        guard let pending, pending.reviewID == reviewID else { return nil }
        guard current(pending) else { discard(); return nil }
        self.pending = nil; queued = pending; return pending
    }
    func resume(_ ticket: Return, editorIsVacant: Bool) -> MerchantBusinessEditorContext? {
        guard queued?.id == ticket.id else { return nil }
        guard editorIsVacant, current(ticket) else { discard(); return nil }
        queued = nil; resumed = ticket; return ticket.context
    }
    func initialDraft(for editorID: UUID) -> MerchantAftercareEvidenceDraft? {
        guard let resumed, resumed.context.id == editorID, current(resumed) else { return nil }
        return resumed.draft
    }
    @discardableResult func synchronize() -> UUID? {
        if let value = pending ?? queued ?? resumed, !current(value) { return discard() }
        return nil
    }
    func beginConfirmation(id: UUID) -> Bool {
        guard visible, active, let owner, let review = owner.coordinator.confirmation,
              review.id == id, case .aftercare = review.mutation else { return false }
        retiredReviewID = id; discard(); return true
    }
    func cancelReview(id: UUID) {
        guard let owner, owner.coordinator.confirmation?.id == id else { return }
        retiredReviewID = id; discard(); owner.cancel()
    }
    private func current(_ ticket: Return) -> Bool {
        guard visible, active, ticket.generation == generation, let owner,
              owner.revision == ticket.ownerRevision, owner.coordinator.confirmation == nil,
              ticket.source.matches(owner) else { return false }
        return true
    }
    private func matches(_ review: MerchantBusinessConfirmation) -> Bool {
        guard let current = owner?.coordinator.confirmation, current.id == review.id,
              case .aftercare(let id, let decision, let text, let evidence) = current.mutation,
              case .aftercare(let originalID, let originalDecision, let originalText, let originalEvidence) = review.mutation else { return false }
        return id == originalID && decision == originalDecision && text.utf8.elementsEqual(originalText.utf8)
            && evidence.map { Data($0.utf8) } == originalEvidence.map { Data($0.utf8) }
    }
}
