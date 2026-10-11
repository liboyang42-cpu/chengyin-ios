import XCTest
@testable import Questify

/// Route/model tests only. Swift/Apple execution and target registration: NOT_RUN.
/// Actual View push/back/reopen/late-load tests are in ClubGovernanceFlowTests.
@MainActor final class ClubLeaderboardMemberRouteTests: XCTestCase {
    private let access = ClubGovernanceFixtureAccess()
    private let reader = ClubLeaderboardUnitProfileReader()
    private let square = ClubLeaderboardUnitSquareReader()
    private var profile: ClubEnrollmentProfileContext { .init(reader: reader, squareReader: square) }
    private var row: ClubGovernanceValue { .object(["memberId": .integer(704), "nickname": .string("A ranked member")]) }
    private func context(operation: ClubGovernanceRead = .leaderboard, epoch: UInt64 = 1,
                         viewerRevision: UInt64 = 1, authorizationGeneration: UUID? = nil,
                         accessIdentity: ObjectIdentifier? = nil) -> ClubGovernanceReadContext {
        .init(operation: operation, scope: .init(clubID: 81), identity: .init(accountID: 701, epoch: epoch),
            viewerRevision: viewerRevision, authorizationGeneration: authorizationGeneration,
            accessIdentity: accessIdentity ?? ObjectIdentifier(access))
    }
    private func snapshot(rows: [ClubGovernanceValue]? = nil, operation: ClubGovernanceRead = .leaderboard,
                          clubID: Int = 81, permission: Bool = true) throws -> ClubGovernanceSnapshot {
        let scope = ClubGovernanceScope(clubID: clubID)
        let permissions: ClubGovernancePermissions?
        if permission { permissions = try ClubGovernancePermissions(value: ClubGovernanceFixtures.permissions, scope: .init(clubID: 81)) }
        else { permissions = nil }
        return .init(operation: operation, scope: scope, permissions: permissions, value: .array(rows ?? [row]))
    }
    private func route() throws -> ClubLeaderboardMemberRoute {
        try XCTUnwrap(ClubLeaderboardMemberRoute(row: row, snapshot: snapshot(), context: context(),
            snapshotGeneration: 3, profile: profile))
    }
    func testExactMemberIDAndExistingReadersWithoutDispatch() throws {
        let selected = try route()
        XCTAssertEqual(selected.memberID, 704)
        XCTAssertNotEqual(selected.memberID, selected.context.scope.clubID)
        XCTAssertTrue(selected.isCurrent(snapshot: try snapshot(), context: context(), snapshotGeneration: 3, profile: profile))
        XCTAssertEqual(reader.reads, 0); XCTAssertEqual(square.reads, 0)
    }
    func testMissingAndInvalidMemberIDsCannotRoute() throws {
        for id in [ClubGovernanceValue.null, .integer(0), .integer(-1), .bool(true),
                   .decimal(7.5), .integer(9_007_199_254_740_992), .string("not an ID")] {
            let malformed = ClubGovernanceValue.object(["memberId": id])
            XCTAssertNil(ClubLeaderboardMemberRoute(row: malformed, snapshot: try snapshot(rows: [malformed]),
                context: context(), snapshotGeneration: 3, profile: profile))
        }
    }
    func testAbsentDuplicateAndContradictoryRowsCannotRoute() throws {
        XCTAssertNil(ClubLeaderboardMemberRoute(row: row, snapshot: try snapshot(rows: []),
            context: context(), snapshotGeneration: 3, profile: profile))
        XCTAssertNil(ClubLeaderboardMemberRoute(row: row, snapshot: try snapshot(rows: [row, row]),
            context: context(), snapshotGeneration: 3, profile: profile))
        let wrongClub = ClubGovernanceValue.object(["memberId": .integer(704), "clubId": .integer(82)])
        XCTAssertNil(ClubLeaderboardMemberRoute(row: wrongClub, snapshot: try snapshot(rows: [wrongClub]),
            context: context(), snapshotGeneration: 3, profile: profile))
    }
    func testWrongOperationClubAndMissingPermissionSnapshotCannotRoute() throws {
        for source in [try snapshot(operation: .customers), try snapshot(clubID: 82), try snapshot(permission: false)] {
            XCTAssertNil(ClubLeaderboardMemberRoute(row: row, snapshot: source, context: context(),
                snapshotGeneration: 3, profile: profile))
        }
        XCTAssertNil(ClubLeaderboardMemberRoute(row: row, snapshot: try snapshot(operation: .customers),
            context: context(operation: .customers), snapshotGeneration: 3, profile: profile))
    }
    func testWrongProfileAccountEpochGuestAndDisabledReaderCannotRoute() throws {
        for identity in [SocialAccountIdentity(accountID: 702, epoch: 1), .init(accountID: 701, epoch: 2), .init(accountID: nil, epoch: 1)] {
            reader.identity = identity
            XCTAssertNil(ClubLeaderboardMemberRoute(row: row, snapshot: try snapshot(), context: context(),
                snapshotGeneration: 3, profile: profile))
        }
        reader.identity = .init(accountID: 701, epoch: 1); reader.isConfigured = false
        XCTAssertNil(ClubLeaderboardMemberRoute(row: row, snapshot: try snapshot(), context: context(),
            snapshotGeneration: 3, profile: profile))
    }
    func testRefreshRemovedSourceAndChangedSameMemberRetireRoute() throws {
        let selected = try route()
        XCTAssertFalse(selected.isCurrent(snapshot: nil, context: context(), snapshotGeneration: 3, profile: profile))
        XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(), context: context(), snapshotGeneration: 4, profile: profile))
        let changed = ClubGovernanceValue.object(["memberId": .integer(704), "nickname": .string("Changed")])
        XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(rows: [changed]), context: context(), snapshotGeneration: 3, profile: profile))
        XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(rows: []), context: context(), snapshotGeneration: 3, profile: profile))
    }
    func testAccountEpochViewerAuthorityAndAccessReplacementRetireRoute() throws {
        let selected = try route(), replacement = ClubGovernanceFixtureAccess()
        for changed in [context(epoch: 2), context(viewerRevision: 2), context(authorizationGeneration: UUID()),
                        context(accessIdentity: ObjectIdentifier(replacement))] {
            XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(), context: changed, snapshotGeneration: 3, profile: profile))
        }
    }
    func testProfileRoleRevisionAccountABAAndReaderReplacementRetireRoute() throws {
        let selected = try route()
        reader.identity = .init(accountID: 701, epoch: 1, role: "replacement role")
        XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(), context: context(), snapshotGeneration: 3, profile: profile))
        reader.identity = .init(accountID: 702, epoch: 2)
        XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(), context: context(), snapshotGeneration: 3, profile: profile))
        reader.identity = .init(accountID: 701, epoch: 3)
        XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(), context: context(), snapshotGeneration: 3, profile: profile))
        reader.identity = .init(accountID: 701, epoch: 1); reader.presentationRevision += 1
        XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(), context: context(), snapshotGeneration: 3, profile: profile))
        let replacement = ClubLeaderboardUnitProfileReader()
        XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(), context: context(), snapshotGeneration: 3,
            profile: .init(reader: replacement, squareReader: square)))
        XCTAssertEqual(reader.reads + replacement.reads, 0)
    }
    func testSquareScopeAndInstanceReplacementRetireRoute() throws {
        let selected = try route(); square.scope = UUID()
        XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(), context: context(), snapshotGeneration: 3, profile: profile))
        XCTAssertFalse(selected.isCurrent(snapshot: try snapshot(), context: context(), snapshotGeneration: 3,
            profile: .init(reader: reader, squareReader: ClubLeaderboardUnitSquareReader())))
        XCTAssertEqual(square.reads, 0)
    }
    func testEachSelectionHasFreshIdentityAndDoesNotShareNavigationLifetime() throws {
        let first = try route(), reopened = try route()
        XCTAssertNotEqual(first, reopened); XCTAssertNotEqual(first.id, reopened.id)
        XCTAssertEqual(first.memberID, reopened.memberID)
    }
}

@MainActor private final class ClubLeaderboardUnitProfileReader: SocialAccountReading {
    var identity = SocialAccountIdentity(accountID: 701, epoch: 1)
    var presentationRevision: UInt64 = 0
    var isConfigured = true
    let isOfflineExample = true
    var reads = 0
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile { reads += 1; throw APIError.notConfigured }
    func informationList() async throws -> [SocialInformation] { throw APIError.notConfigured }
    func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
    func invitationHistory(page: Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
}
@MainActor private final class ClubLeaderboardUnitSquareReader: SquareReading {
    var scope = UUID()
    let isConfigured = true, isOfflineExample = true, isSignedIn = true
    var reads = 0
    func squareFeed(query: SquareQuery, cursor: SquareCursor?) async throws -> SquareFeedPage { reads += 1; throw APIError.notConfigured }
    func squareDetail(id: Int) async throws -> SquarePost { reads += 1; throw APIError.notConfigured }
    func squareComments(postID: Int, pageNumber: Int) async throws -> SquareCommentPage { reads += 1; throw APIError.notConfigured }
}
