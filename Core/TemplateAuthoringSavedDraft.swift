import Foundation

/// Member-template ID returned by this exact acknowledged /draft operation.
/// Never a local draft UUID, public-library ID, simulation or inferred list result.
public struct TemplateAuthoringSavedDraft: Codable, Equatable {
    public let operationID: UUID
    public let ownerKey: String
    public let identity: TemplateAuthoringIdentity
    public let memberTemplateID: MemberPlayTemplateID
    public let requestHash: String
    init(operationID: UUID, ownerKey: String, identity: TemplateAuthoringIdentity,
         memberTemplateID: MemberPlayTemplateID, request: TemplateAuthoringRequest) throws {
        guard request.path == "/api/template/draft", TemplateAuthoringContract.permitsRemoteConfiguration(request),
              let bytes = ProjectEditPendingMaterials.exactData(request) else { throw TemplateAuthoringError.invalidContract }
        self.operationID = operationID; self.ownerKey = ownerKey; self.identity = identity
        self.memberTemplateID = memberTemplateID; requestHash = ProjectStoryImageTarget.hash(bytes)
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
        guard pending.terminal, pending.acknowledged == true, pending.operationID == operationID, pending.identity == identity,
              pending.ownerKey.utf8.elementsEqual(ownerKey.utf8), ownerKey.utf8.elementsEqual(session.ownerKey.utf8),
              pending.request.path == "/api/template/draft", TemplateAuthoringContract.permitsRemoteConfiguration(pending.request),
              let bytes = ProjectEditPendingMaterials.exactData(pending.request) else { return false }
        return requestHash == ProjectStoryImageTarget.hash(bytes)
    }
    public static func responseID(_ data: Data, request: TemplateAuthoringRequest) throws -> MemberPlayTemplateID {
        guard request.path == "/api/template/draft", TemplateAuthoringContract.permitsRemoteConfiguration(request) else { throw TemplateAuthoringError.invalidContract }
        let response = try ApprovedTopicReleaseWire.envelope(data)
        guard response["code"]?.integer == 200 else { throw TemplateAuthoringError.invalidContract }
        let raw = response["data"]?.object?["id"] ?? response["data"]
        guard let number = raw?.integer, let id = MemberPlayTemplateID(rawValue: number) else { throw TemplateAuthoringError.invalidContract }
        return id
    }
}
public struct TemplateAuthoringSubmission {
    public let outcome: TemplateAuthoringOutcome
    public let savedMemberTemplateID: MemberPlayTemplateID?
}
