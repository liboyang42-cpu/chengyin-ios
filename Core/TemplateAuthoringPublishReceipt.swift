import Foundation

/// Acknowledged /publish returns a canonical member-template ID, not a public-library ID.
/// Receipt means submitted for review. It does not mean approved, listed or playable.
public struct TemplateAuthoringPublishReceipt: Codable, Equatable {
    public let operationID: UUID
    public let ownerKey: String
    public let identity: TemplateAuthoringIdentity
    public let memberTemplateID: MemberPlayTemplateID
    public let requestHash: String
    init(operationID: UUID, ownerKey: String, identity: TemplateAuthoringIdentity,
         memberTemplateID: MemberPlayTemplateID, request: TemplateAuthoringRequest) throws {
        guard request.path == "/api/template/publish", TemplateAuthoringContract.permitsRemoteConfiguration(request),
              let data = ProjectEditPendingMaterials.exactData(request) else { throw TemplateAuthoringError.invalidContract }
        self.operationID = operationID; self.ownerKey = ownerKey; self.identity = identity
        self.memberTemplateID = memberTemplateID; requestHash = ProjectStoryImageTarget.hash(data)
    }
    private enum CodingKeys: String, CodingKey { case operationID, ownerKey, identity, memberTemplateID, requestHash }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operationID = try c.decode(UUID.self, forKey: .operationID); ownerKey = try c.decode(String.self, forKey: .ownerKey)
        identity = try c.decode(TemplateAuthoringIdentity.self, forKey: .identity); requestHash = try c.decode(String.self, forKey: .requestHash)
        guard !ownerKey.isEmpty, ApprovedTopicReleasePreparation.validHash(requestHash),
              let id = MemberPlayTemplateID(rawValue: try c.decode(Int.self, forKey: .memberTemplateID)) else { throw TemplateAuthoringError.invalidContract }
        memberTemplateID = id
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(operationID, forKey: .operationID); try c.encode(ownerKey, forKey: .ownerKey)
        try c.encode(identity, forKey: .identity); try c.encode(memberTemplateID.rawValue, forKey: .memberTemplateID); try c.encode(requestHash, forKey: .requestHash)
    }
    public func matches(_ pending: TemplateAuthoringPending, session: TemplateAuthoringSession) -> Bool {
        guard pending.terminal, pending.acknowledged == true, pending.savedDraft == nil, pending.publishedReceipt == self,
              pending.operationID == operationID, pending.identity == identity,
              pending.ownerKey.utf8.elementsEqual(ownerKey.utf8), ownerKey.utf8.elementsEqual(session.ownerKey.utf8),
              pending.request.path == "/api/template/publish", TemplateAuthoringContract.permitsRemoteConfiguration(pending.request),
              let data = ProjectEditPendingMaterials.exactData(pending.request) else { return false }
        return requestHash == ProjectStoryImageTarget.hash(data)
    }
    public static func responseID(_ data: Data, request: TemplateAuthoringRequest) throws -> MemberPlayTemplateID {
        guard request.path == "/api/template/publish", TemplateAuthoringContract.permitsRemoteConfiguration(request) else { throw TemplateAuthoringError.invalidContract }
        let response = try ApprovedTopicReleaseWire.envelope(data)
        // Audited backend returns AjaxResult.success(Long), not a draft DTO or guessed list row.
        guard response["code"]?.integer == 200, let value = response["data"]?.integer,
              let id = MemberPlayTemplateID(rawValue: value) else { throw TemplateAuthoringError.invalidContract }
        return id
    }
}

public struct TemplateAuthoringPublishResult: Equatable, Identifiable {
    public static let displayMilliseconds = 2_000
    public let receipt: TemplateAuthoringPublishReceipt
    public let session: TemplateAuthoringSession
    public let title: String
    public var id: UUID { receipt.operationID }
    public var memberTemplateID: MemberPlayTemplateID { receipt.memberTemplateID }
    public init?(receipt: TemplateAuthoringPublishReceipt?, pending: TemplateAuthoringPending?, session: TemplateAuthoringSession?, identity: TemplateAuthoringIdentity) {
        guard let receipt, let pending, let session, pending.publishedReceipt == receipt,
              receipt.identity == identity, pending.identity == identity, receipt.matches(pending, session: session),
              case .json(let fields) = pending.request.body, let title = fields["title"]?.string else { return nil }
        self.receipt = receipt; self.session = session; self.title = title
    }
    @MainActor public init?(coordinator: TemplateAuthoringCoordinator) {
        guard coordinator.state == .acknowledged else { return nil }
        self.init(receipt: coordinator.publishedReceipt, pending: coordinator.pending, session: coordinator.session, identity: coordinator.identity)
    }
    @MainActor public func isCurrent(in coordinator: TemplateAuthoringCoordinator) -> Bool {
        guard let current = Self(coordinator: coordinator) else { return false }
        return current == self && TemplateAuthoringSavedResult.exactSession(current.session, session)
    }
}
