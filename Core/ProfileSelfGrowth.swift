import Foundation

/// A captured association from the existing account host, never an endpoint permission.
public struct ProfileSelfGrowthContext: Hashable {
    public let memberID: Int
    public let accountReader: ObjectIdentifier
    public let viewer: SocialAccountIdentity
    public let viewerRevision: UInt64
    public let growthReader: ObjectIdentifier
    public let growthScope: UUID
    @MainActor public static func capture(memberID: Int, accountReader: any SocialAccountReading,
        growthReader: any GrowthCenterReading, owner: SocialAccountIdentity, ownerScope: UUID,
        isCurrent: Bool) -> Self? {
        guard isCurrent, memberID > 0, owner.accountID == memberID, accountReader.identity == owner,
              accountReader.isConfigured, growthReader.isAuthenticated, growthReader.isConfigured,
              growthReader.scope == ownerScope else { return nil }
        return .init(memberID: memberID, accountReader: ObjectIdentifier(accountReader), viewer: owner,
            viewerRevision: accountReader.presentationRevision, growthReader: ObjectIdentifier(growthReader), growthScope: ownerScope)
    }
}
/// Used by both the summary and the existing full center/leaderboard. All queued reads are fenced.
@MainActor public final class ProfileSelfGrowthScopedReader: GrowthCenterReading {
    public let scope = UUID()
    private let expected: ProfileSelfGrowthContext
    private let accountReader: any SocialAccountReading
    private let reader: any GrowthCenterReading
    private let isCurrent: @MainActor () -> Bool
    public init(context: ProfileSelfGrowthContext, accountReader: any SocialAccountReading,
        growthReader: any GrowthCenterReading, isCurrent: @escaping @MainActor () -> Bool) {
        expected = context; self.accountReader = accountReader; reader = growthReader; self.isCurrent = isCurrent
    }
    private var matches: Bool {
        ProfileSelfGrowthContext.capture(memberID: expected.memberID, accountReader: accountReader,
            growthReader: reader, owner: expected.viewer, ownerScope: expected.growthScope, isCurrent: isCurrent()) == expected
    }
    public var isAuthenticated: Bool { matches && reader.isAuthenticated }
    public var isConfigured: Bool { matches && reader.isConfigured }
    public var isOfflineExample: Bool { reader.isOfflineExample }
    public func overview() async throws -> GrowthCenterOverview { try await read { try await reader.overview() } }
    public func leaderboard(query: GrowthBoardQuery) async throws -> GrowthLeaderboard {
        try await read { try await reader.leaderboard(query: query) }
    }
    private func read<Value>(_ operation: () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard matches else { throw CancellationError() }
        do {
            let result = try await operation()
            try Task.checkCancellation()
            guard matches else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, matches else { throw CancellationError() }
            throw error
        }
    }
}

/// Mini loadGrowthBundle's six metrics. Unknown/negative values never become invented zeroes.
public struct ProfileSelfGrowthSummary: Equatable {
    public let level: Int?
    public let experience: Int?
    public let points: Int?
    public let checkins: Int?
    public let mileage: Double?
    public let streakDays: Int?
    public let centerIssue: GrowthCenterIssue?
    public let progressIssue: GrowthCenterIssue?
    public init(_ overview: GrowthCenterOverview) {
        let center = overview.center.value, progress = overview.progress.value
        level = GrowthCenterFormatting.nonnegative(progress?.level ?? center?.level).map { max(1, $0) }
        experience = GrowthCenterFormatting.nonnegative(center?.experience)
        points = GrowthCenterFormatting.nonnegative(center?.points)
        checkins = GrowthCenterFormatting.nonnegative(progress?.totalCheckins)
        mileage = GrowthCenterFormatting.mileage(progress?.totalMileage)
        streakDays = GrowthCenterFormatting.nonnegative(progress?.streakDays)
        centerIssue = overview.center.issue; progressIssue = overview.progress.issue
    }
}
