import Foundation

/// A quick-start read scope, not a createSeries authorization.
public struct ClubSessionQuickStartContext: Equatable {
    public let clubID: Int
    public let owner: Bool
    public let identity: ClubReadIdentity
    public let readerID: ObjectIdentifier
    public let accessID: ObjectIdentifier
    public let accessIdentity: ClubReadIdentity?
    public let authorizationGeneration: UUID?
    public let namespace: String
    public let viewerRevision: UInt64
    public let configured: Bool
    @MainActor public init(club: ClubRecord, reader: any ClubReading, access: any ClubGovernanceAccess, viewerRevision: UInt64) {
        clubID = club.id; owner = club.isOwner; identity = reader.clubIdentity
        readerID = ObjectIdentifier(reader); accessID = ObjectIdentifier(access); accessIdentity = access.identity
        authorizationGeneration = access.authorizationGeneration; namespace = access.storageNamespace
        self.viewerRevision = viewerRevision; configured = reader.isClubConfigured && access.isConfigured
    }
    public var canRead: Bool { owner && clubID > 0 && configured && (identity.accountID ?? 0) > 0 && identity == accessIdentity }
    public var topicsContext: ClubGovernanceReadContext {
        .init(operation: .eventTopics, scope: .init(clubID: clubID), identity: identity, viewerRevision: viewerRevision,
              authorizationGeneration: authorizationGeneration, readerIdentity: readerID, accessIdentity: accessID)
    }
    @MainActor public func matches(reader: any ClubReading, access: any ClubGovernanceAccess, viewerRevision: UInt64) -> Bool {
        canRead && readerID == ObjectIdentifier(reader) && reader.isClubConfigured && reader.clubIdentity == identity &&
        accessID == ObjectIdentifier(access) && access.isConfigured && access.identity == identity &&
        access.authorizationGeneration == authorizationGeneration && access.storageNamespace == namespace && self.viewerRevision == viewerRevision
    }
}

public struct ClubSessionQuickStartTopic: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let originClubID: Int?
    public let startDate: String?
    public let endDate: String?
    public func originKey(currentClubID: Int) -> String {
        guard let originClubID else { return "club.sessionStart.originUnknown" }
        return originClubID == currentClubID ? "club.sessionStart.owned" : "club.sessionStart.cooperative"
    }
}

public struct ClubSessionQuickStartTopics: Equatable {
    public let rows: [ClubSessionQuickStartTopic]
    private let context: ClubSessionQuickStartContext
    public init(context: ClubSessionQuickStartContext, snapshot: ClubGovernanceSnapshot) throws {
        guard context.canRead, context.topicsContext.accepts(snapshot) else { throw ClubGovernanceFailure.targetChanged }
        guard snapshot.permissions?.allows(ClubGovernanceRead.eventTopics.permission, scope: snapshot.scope) == true else { throw ClubGovernanceFailure.forbidden }
        let accepted = try ClubGovernanceValidation.validate(snapshot.value, operation: .eventTopics, scope: snapshot.scope)
        guard let list = accepted.array else { throw ClubGovernanceFailure.malformed }
        rows = try list.map { row in
            guard let id = row["id"].int, id > 0 else { throw ClubGovernanceFailure.malformed }
            // This is the publisher's club, not the club authorized to manage this cooperative topic.
            let origin = row["clubId"].int.flatMap { $0 > 0 ? $0 : nil }
            return .init(id: id, name: Self.text(row["name"])?.trimmingCharacters(in: .whitespacesAndNewlines),
                         originClubID: origin, startDate: Self.text(row["startDate"]), endDate: Self.text(row["endDate"]))
        }
        self.context = context
    }
    private static func text(_ value: ClubGovernanceValue) -> String? {
        guard let text = value.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }; return text
    }
    public func target(topicID: Int, context: ClubSessionQuickStartContext, snapshotID: UUID) -> ClubSessionQuickStartTarget? {
        guard self.context == context, context.canRead, let row = rows.first(where: { $0.id == topicID }) else { return nil }
        return .init(topic: row, context: context, snapshotID: snapshotID)
    }
}

public struct ClubSessionQuickStartTarget: Equatable, Identifiable {
    public let id = UUID()
    public let topic: ClubSessionQuickStartTopic
    public let context: ClubSessionQuickStartContext
    private let snapshotID: UUID
    fileprivate init(topic: ClubSessionQuickStartTopic, context: ClubSessionQuickStartContext, snapshotID: UUID) {
        self.topic = topic; self.context = context; self.snapshotID = snapshotID
    }
    public var scope: ClubGovernanceScope { .init(clubID: context.clubID, topicID: topic.id) }
    public var seed: [String: ClubGovernanceValue] { ["recurrenceType": .string("ONCE")] }
    public func isCurrent(topics: ClubSessionQuickStartTopics?, context: ClubSessionQuickStartContext, snapshotID: UUID) -> Bool {
        self.context == context && context.canRead && self.snapshotID == snapshotID && topics?.target(topicID: topic.id, context: context, snapshotID: snapshotID)?.topic == topic
    }
}
