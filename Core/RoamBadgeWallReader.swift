import Foundation

public struct RoamBadgeWallReadOwner: Equatable, Hashable {
    public let roamReaderID: ObjectIdentifier
    public let scopeKey: String?
    public let accountID: Int?
    public let epoch: UInt64?
    public let profileReaderID: ObjectIdentifier
    public let profileIdentity: ProfileReadIdentity?
    public let profileConfigured: Bool
    @MainActor public init(roam: any RoamExperienceReading, profile: any ProfileReading) {
        let identity = roam.identity
        roamReaderID = ObjectIdentifier(roam); scopeKey = identity?.scope.storageKey
        accountID = identity?.scope.accountID; epoch = identity?.epoch
        profileReaderID = ObjectIdentifier(profile); profileIdentity = profile.identity; profileConfigured = profile.isConfigured
    }
    public var hasMatchingAccount: Bool {
        scopeKey != nil && accountID != nil && accountID == profileIdentity?.accountID && epoch == profileIdentity?.epoch
    }
}

/// P005 enters the existing account badge wall. This bridge delegates only its actual badge read,
/// never the wider Profile order/participant contract. It stores no results or credentials.
@MainActor public final class RoamBadgeWallReader: ProfileReading {
    private let roam: any RoamExperienceReading
    private let profile: any ProfileReading
    public let origin: RoamBadgeWallReadOwner
    public init(roam: any RoamExperienceReading, profile: any ProfileReading) {
        self.roam = roam; self.profile = profile; origin = .init(roam: roam, profile: profile)
    }
    public var currentOwner: RoamBadgeWallReadOwner { .init(roam: roam, profile: profile) }
    public var isCurrent: Bool { origin.hasMatchingAccount && origin == currentOwner }
    public var isConfigured: Bool { isCurrent && profile.isConfigured }
    public var identity: ProfileReadIdentity? { isCurrent ? profile.identity : nil }
    public func profileBadges() async throws -> ProfileBadgeWall {
        try Task.checkCancellation()
        guard isCurrent else { throw APIError.unauthorized }
        guard profile.isConfigured else { throw APIError.notConfigured }
        do {
            let result = try await profile.profileBadges()
            try Task.checkCancellation()
            guard isCurrent else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, isCurrent else { throw CancellationError() }
            throw error
        }
    }
    public func profileOrders() async throws -> [ProfileOrder] { throw APIError.notConfigured }
    public func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    public func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.notConfigured }
    public func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
}
