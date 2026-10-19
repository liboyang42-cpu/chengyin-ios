import XCTest
@testable import QuestifyCore

/// Mini-program subpackageRoam/my-teams grouping over already-read team/my and my-applications rows.
@MainActor final class NearbyMyTeamGroupsTests: XCTestCase {
    private func teams(_ json: String) throws -> [OwnedTeam] { try JSONDecoder().decode([OwnedTeam].self, from: Data(json.utf8)) }
    private func applications(_ json: String) throws -> [NearbyMyApplication] { try JSONDecoder().decode([NearbyMyApplication].self, from: Data(json.utf8)) }

    func testGroupsFollowMiniProgramOrderAndOmitEndedOrEmptyGroups() throws {
        let joined = try teams(#"[{"id":1,"title":"Led","status":0,"leaderMemberId":"42"},{"id":2,"title":"Member","status":1,"leaderMemberId":9},{"id":3,"title":"Ended","status":3,"leaderMemberId":42}]"#)
        let apps = try applications(#"[{"teamId":4,"title":"Wait","applyStatus":"PENDING"},{"teamId":5,"title":"No","applyStatus":"REJECTED"},{"teamId":2,"title":"Dup","applyStatus":"PENDING"}]"#)
        let groups = NearbyTeamBridge.myGroups(NearbyTeamBridge.myRows(joined: joined, applications: apps), viewerAccountID: 42)
        XCTAssertEqual(groups.map(\.kind), [.leading, .approved, .pending, .rejected])
        XCTAssertEqual(groups.map { $0.rows.map(\.id.rawValue) }, [[1], [2], [4], [5]])
        XCTAssertEqual(NearbyMyTeamGroup.Kind.statsOrder.map { NearbyMyTeamGroup.count($0, in: groups) }, [1, 1, 1, 1])
        XCTAssertEqual(groups.first?.kind.titleKey, "nearby.mine.group.leading")
    }

    func testMissingOrForeignLeaderIsNeverPromotedToLeading() throws {
        let joined = try teams(#"[{"id":1,"title":"A","status":0},{"id":2,"title":"B","status":0,"leaderMemberId":0},{"id":3,"title":"C","status":2,"leaderMemberId":7}]"#)
        XCTAssertNil(joined[1].leaderMemberID)
        let rows = NearbyTeamBridge.myRows(joined: joined, applications: [])
        XCTAssertEqual(NearbyTeamBridge.myGroups(rows, viewerAccountID: 42).map(\.kind), [.approved])
        XCTAssertEqual(NearbyTeamBridge.myGroups(rows, viewerAccountID: nil).map(\.kind), [.approved])
        XCTAssertEqual(NearbyTeamBridge.myGroups(rows, viewerAccountID: 7).map(\.kind), [.leading, .approved])
    }

    func testEmptyInputsProduceNoGroupsAndSyntheticFixtureMatchesAccount() throws {
        XCTAssertTrue(NearbyTeamBridge.myGroups([], viewerAccountID: 42).isEmpty)
        let fixture = NearbyTeamBridge.myRows(joined: NearbyTeamSyntheticFixtures.joinedTeams, applications: [])
        let groups = NearbyTeamBridge.myGroups(fixture, viewerAccountID: NearbyTeamSyntheticFixtures.session.accountID)
        XCTAssertEqual(groups.map { $0.rows.map(\.id.rawValue) }, [[503], [505]])
    }
}
