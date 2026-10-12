import Foundation

/// P046 edits the existing profile fields only when Apply is explicitly chosen.
public enum ClubProfileChoiceKind: String, Equatable { case type, directions }
public struct ClubProfileChoiceDraft: Equatable {
    public let kind: ClubProfileChoiceKind
    public let source: ClubOperationsDraft
    public private(set) var type: String
    public private(set) var directions: [String]
    public init(kind: ClubProfileChoiceKind, source: ClubOperationsDraft) {
        self.kind = kind; self.source = source; type = source.clubType; directions = source.activityPrefs
    }
    @discardableResult public mutating func selectType(_ value: String) -> Bool {
        guard kind == .type, ClubOperationsCatalog.types.contains(value) else { return false }
        type = value; return true
    }
    @discardableResult public mutating func toggleDirection(_ value: String) -> Bool {
        guard kind == .directions, ClubOperationsCatalog.directions.contains(value) else { return false }
        if directions.contains(value) { directions.removeAll { $0 == value }; return true }
        guard directions.count < 3 else { return false }
        directions.append(value); return true
    }
    public var isValid: Bool {
        switch kind {
        case .type: return type == source.clubType || ClubOperationsCatalog.types.contains(type)
        case .directions:
            return directions == source.activityPrefs ||
                (directions.count <= 3 && Set(directions).count == directions.count && directions.allSatisfy(ClubOperationsCatalog.directions.contains))
        }
    }
    public func applying(to current: ClubOperationsDraft) throws -> ClubOperationsDraft {
        guard current == source else { throw ClubOperationsBlock.changed }
        guard isValid else { throw ClubOperationsBlock.invalidSelection }
        var next = current
        switch kind { case .type: next.clubType = type; case .directions: next.activityPrefs = directions }
        return next
    }
}

/// The original loaded edit profile is a scope proof, never a write grant.
public struct ClubProfileChoiceContext: Equatable {
    public let clubID: Int
    public let identity: ClubReadIdentity
    public let accessID: ObjectIdentifier
    public let sourceRevision: UUID
    public let profile: ClubOperationsProfile
    @MainActor public init?(target: ClubOperationsTarget, identity: ClubReadIdentity?, access: any ClubOperationsAccess,
                            profile: ClubOperationsProfile?, sourceRevision: UUID) {
        guard case .club(let id) = target, id > 0, let profile, profile.club.id == id, profile.club.canGovern,
              let identity, identity.isSignedIn, (identity.accountID ?? 0) > 0, identity == access.identity, access.isConfigured else { return nil }
        clubID = id; self.identity = identity; accessID = ObjectIdentifier(access)
        self.profile = profile; self.sourceRevision = sourceRevision
    }
    @MainActor public func matches(target: ClubOperationsTarget, identity: ClubReadIdentity?, access: any ClubOperationsAccess,
                                  profile: ClubOperationsProfile?, sourceRevision: UUID) -> Bool {
        Self(target: target, identity: identity, access: access, profile: profile, sourceRevision: sourceRevision) == self
    }
}
