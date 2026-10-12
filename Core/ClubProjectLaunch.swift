import Foundation

public struct ClubProjectLaunchContext: Equatable {
    public let clubID: Int
    public let owner: Bool
    public let identity: ClubReadIdentity
    public let readerID: ObjectIdentifier
    public let editorContextID: String
    public let configured: Bool
    @MainActor public init(club: ClubRecord, reader: any ClubReading, editorContextID: String) {
        clubID = club.id; owner = club.isOwner; identity = reader.clubIdentity
        readerID = ObjectIdentifier(reader); self.editorContextID = editorContextID; configured = reader.isClubConfigured
    }
    public var canRead: Bool { owner && clubID > 0 && (identity.accountID ?? 0) > 0 && configured && !editorContextID.isEmpty }
    @MainActor public func matches(reader: any ClubReading, editorContextID: String) -> Bool {
        canRead && readerID == ObjectIdentifier(reader) && reader.isClubConfigured && reader.clubIdentity == identity && self.editorContextID == editorContextID
    }
    public func seed(product: ProjectEditProduct) throws -> ProjectEditDraft {
        guard canRead else { throw ClubGovernanceFailure.targetChanged }
        var seed = ProjectEditDraft(product: product)
        seed.clubID = clubID
        return seed
    }
}
/// Ephemeral local destination, never an owner grant for project submission.
public struct ClubProjectLaunchTarget: Equatable, Identifiable {
    public let id = UUID()
    public let context: ClubProjectLaunchContext
    public let seed: ProjectEditDraft
    public init(context: ClubProjectLaunchContext, product: ProjectEditProduct) throws {
        self.context = context; seed = try context.seed(product: product)
    }
    public func matches(projectSession: ProjectEditSession?) -> Bool {
        guard let projectSession else { return false }
        return projectSession.accountID == context.identity.accountID && projectSession.epoch == context.identity.epoch
    }
}
