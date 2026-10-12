import Foundation

/// A saved-draft result is backed by the exact existing positive-ID receipt, never a title/list guess.
public struct TemplateAuthoringSavedResult: Equatable, Identifiable {
    public static let displayMilliseconds = 2_000
    public let receipt: TemplateAuthoringSavedDraft
    public let session: TemplateAuthoringSession
    public let title: String
    public var id: UUID { receipt.operationID }
    public var memberTemplateID: MemberPlayTemplateID { receipt.memberTemplateID }
    public init?(receipt: TemplateAuthoringSavedDraft?, pending: TemplateAuthoringPending?, session: TemplateAuthoringSession?, identity: TemplateAuthoringIdentity) {
        guard let receipt, let pending, let session, pending.savedDraft == receipt,
              receipt.identity == identity, pending.identity == identity,
              receipt.matches(pending, session: session), case .json(let fields) = pending.request.body,
              let title = fields["title"]?.string else { return nil }
        self.receipt = receipt; self.session = session; self.title = title
    }
    @MainActor public init?(coordinator: TemplateAuthoringCoordinator) {
        guard coordinator.state == .acknowledged else { return nil }
        self.init(receipt: coordinator.savedDraft, pending: coordinator.pending, session: coordinator.session, identity: coordinator.identity)
    }
    @MainActor public func isCurrent(in coordinator: TemplateAuthoringCoordinator) -> Bool {
        guard let current = Self(coordinator: coordinator) else { return false }
        return current == self && Self.exactSession(current.session, session)
    }
    public static func exactSession(_ lhs: TemplateAuthoringSession, _ rhs: TemplateAuthoringSession) -> Bool {
        lhs.accountID == rhs.accountID && lhs.epoch == rhs.epoch &&
        lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8) &&
        lhs.authorizationRevision.utf8.elementsEqual(rhs.authorizationRevision.utf8)
    }
}
