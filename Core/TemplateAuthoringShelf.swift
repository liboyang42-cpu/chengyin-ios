import Foundation

public enum TemplateOwnShelfAction: String, Codable { case libraryStatus, remove }
public struct TemplateOwnShelfReview: Equatable, Identifiable {
    public let id: UUID
    public let templateID: AuthoringPlayTemplateID
    public let title: String
    public let action: TemplateOwnShelfAction
    public let desiredPublishStatus: Int?
    public let request: TemplateAuthoringRequest
    let session: TemplateAuthoringSession
    let baseline: DiscoveryPlayTemplate
    let generation: Int
    init(row: DiscoveryPlayTemplate, action: TemplateOwnShelfAction, session: TemplateAuthoringSession, generation: Int) throws {
        guard let identity = AuthoringPlayTemplateID(rawValue: row.id) else { throw TemplateAuthoringError.invalidContract }
        id = UUID(); templateID = identity; title = row.title; self.action = action
        desiredPublishStatus = action == .libraryStatus ? (row.publishStatus == 1 ? 0 : 1) : nil
        request = action == .remove ? TemplateAuthoringContract.remove(id: identity) : TemplateAuthoringContract.libraryStatus(id: identity, current: row.publishStatus)
        self.session = session; baseline = row; self.generation = generation
    }
}
/// One conservative, durable own-shelf write lock per account/region. Separate from
/// the existing create-draft journal, but using the same account-scoped secure store.
public struct TemplateOwnShelfPending: Codable, Equatable {
    public let operationID: UUID
    public let ownerKey: String
    public let templateID: AuthoringPlayTemplateID
    public let action: TemplateOwnShelfAction
    public let desiredPublishStatus: Int?
    public let request: TemplateAuthoringRequest
    public var acknowledged: Bool = false
    init(review: TemplateOwnShelfReview) {
        operationID = review.id; ownerKey = review.session.ownerKey; templateID = review.templateID
        action = review.action; desiredPublishStatus = review.desiredPublishStatus; request = review.request
    }
    /// A 100-row response is capped, not a complete collection. Missing identity
    /// cannot establish removal there. Unknown responses are never reconciled here.
    public func matchesAcknowledgedReadback(_ rows: [DiscoveryPlayTemplate]) -> Bool {
        guard acknowledged else { return false }
        let matches = rows.filter { $0.id == templateID.rawValue }
        switch action {
        case .libraryStatus: return matches.count == 1 && matches[0].publishStatus == desiredPublishStatus
        case .remove: return rows.count < 100 && matches.isEmpty
        }
    }
}
