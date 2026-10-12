import Foundation

public enum ClubInvitationFeedbackDirection: String, CaseIterable, Hashable { case received, sent }
public struct ClubInvitationFeedbackKey: Hashable {
    public let direction: ClubInvitationFeedbackDirection
    public let invitationID: Int
}
public struct ClubInvitationFeedbackRow: Identifiable, Equatable {
    public let id: ClubInvitationFeedbackKey
    public let topicID: Int?
    public let partnerName: String?
    public let topicName: String?
    public let createdAt: String?
    public let message: String?
    public let status: Int?
    public var statusKey: String { "club.inviteFeedback.status." + (status.map(String.init) ?? "unknown") }
}
public struct ClubInvitationFeedbackContext: Equatable {
    public let clubID: Int
    public let owner: Bool
    public let identity: ClubReadIdentity
    public let clubReaderID: ObjectIdentifier
    public let readerID: ObjectIdentifier
    public let accessID: ObjectIdentifier
    public let session: CoopFlowSession?
    public let authorizationGeneration: UUID?
    public let namespace: String
    public let configured: Bool
    public let accessIdentity: ClubReadIdentity?
    @MainActor public init(club: ClubRecord, clubReader: any ClubReading, reader: any CoopFlowReading, access: any ClubGovernanceAccess) {
        clubID = club.id; owner = club.isOwner; identity = clubReader.clubIdentity
        clubReaderID = ObjectIdentifier(clubReader); readerID = ObjectIdentifier(reader); accessID = ObjectIdentifier(access)
        session = reader.session; authorizationGeneration = access.authorizationGeneration; namespace = access.storageNamespace
        configured = clubReader.isClubConfigured && access.isConfigured; accessIdentity = access.identity
    }
    public var canRead: Bool {
        owner && clubID > 0 && configured && (identity.accountID ?? 0) > 0 && identity == accessIdentity &&
        identity.accountID == session?.accountID && identity.epoch == session?.epoch
    }
    public var topicsContext: ClubGovernanceReadContext {
        .init(operation: .topics, scope: .init(clubID: clubID), identity: identity, viewerRevision: 0,
              authorizationGeneration: authorizationGeneration, accessIdentity: accessID)
    }
    @MainActor public func matches(clubReader: any ClubReading, reader: any CoopFlowReading, access: any ClubGovernanceAccess) -> Bool {
        canRead && clubReader.isClubConfigured && identity == clubReader.clubIdentity && clubReaderID == ObjectIdentifier(clubReader) &&
        session == reader.session && readerID == ObjectIdentifier(reader) && accessID == ObjectIdentifier(access) && access.isConfigured &&
        access.identity == identity && access.authorizationGeneration == authorizationGeneration && access.storageNamespace == namespace
    }
}

/// Only scoped, display-safe fields survive this projection. No contacts or financial terms.
public struct ClubInvitationFeedbackSnapshot: Equatable {
    public let clubID: Int
    public let rows: [ClubInvitationFeedbackRow]
    private let context: ClubInvitationFeedbackContext
    public init(context: ClubInvitationFeedbackContext, topics: ClubGovernanceSnapshot, invitations: CoopFlowJSON) throws {
        let clubID = context.clubID
        guard context.canRead, clubID > 0, topics.operation == .topics, topics.scope == .init(clubID: clubID) else { throw ClubGovernanceFailure.targetChanged }
        let accepted = try ClubGovernanceValidation.validate(topics.value, operation: .topics, scope: topics.scope)
        guard let topics = accepted.array, let received = invitations["received"].rows, let sent = invitations["sent"].rows else { throw ClubGovernanceFailure.malformed }
        let ids = Set(topics.compactMap { $0["id"].int })
        var rows: [ClubInvitationFeedbackRow] = [], keys = Set<ClubInvitationFeedbackKey>()
        for (direction, source) in [(ClubInvitationFeedbackDirection.received, received), (.sent, sent)] {
            for raw in source {
                guard case .object = raw else { throw ClubGovernanceFailure.malformed }
                let included = direction == .received
                    ? raw["toType"].text == "club" && raw["toId"].integer == clubID
                    : raw["topicId"].integer.map(ids.contains) == true
                guard included else { continue }
                guard let id = raw["id"].integer, id > 0 else { throw ClubGovernanceFailure.malformed }
                let key = ClubInvitationFeedbackKey(direction: direction, invitationID: id)
                guard keys.insert(key).inserted else { throw ClubGovernanceFailure.malformed }
                let topic = raw["topicId"].integer.flatMap { $0 > 0 ? $0 : nil }
                let topicName = Self.text(raw["topicName"]), partner = Self.text(raw["partner"]["name"])
                let status = raw["status"].integer.flatMap { (0...5).contains($0) ? $0 : nil }
                rows.append(.init(id: key, topicID: topic, partnerName: partner ?? (direction == .received ? topicName : nil),
                                  topicName: topicName, createdAt: Self.text(raw["createTime"]), message: Self.text(raw["message"]), status: status))
            }
        }
        self.clubID = clubID; self.rows = rows; self.context = context
    }
    private static func text(_ raw: CoopFlowJSON) -> String? {
        guard case .string(let text) = raw, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }; return text
    }
    public func rows(in direction: ClubInvitationFeedbackDirection) -> [ClubInvitationFeedbackRow] { rows.filter { $0.id.direction == direction } }
    public func target(key: ClubInvitationFeedbackKey, context: ClubInvitationFeedbackContext, snapshotID: UUID) -> ClubInvitationFeedbackTarget? {
        guard self.context == context, context.canRead, context.clubID == clubID, let row = rows.first(where: { $0.id == key }) else { return nil }
        return .init(row: row, context: context, snapshotID: snapshotID)
    }
}
public struct ClubInvitationFeedbackTarget: Identifiable, Equatable {
    public let id = UUID()
    public let row: ClubInvitationFeedbackRow
    private let context: ClubInvitationFeedbackContext
    private let snapshotID: UUID
    fileprivate init(row: ClubInvitationFeedbackRow, context: ClubInvitationFeedbackContext, snapshotID: UUID) {
        self.row = row; self.context = context; self.snapshotID = snapshotID
    }
    public func isCurrent(snapshot: ClubInvitationFeedbackSnapshot?, context: ClubInvitationFeedbackContext, snapshotID: UUID) -> Bool {
        self.context == context && context.canRead && self.snapshotID == snapshotID &&
        snapshot?.clubID == context.clubID && snapshot?.rows.contains(row) == true
    }
}
