import XCTest
@testable import QuestifyCore

final class TeamClubEligibilityProjectionTests: XCTestCase {
    private func selection(mode: String = "TEAM", clubs: [Int] = [11, 22]) -> OrdinaryCityCourseSelection {
        OrdinaryCityCourseSelection(
            courseID: 1001, topicID: 2001, cityTimeZoneIdentifier: "Asia/Shanghai",
            publishedRuleVersionID: "rule-v3", safetyVersionID: "safety-v2",
            participationMode: mode, requiredClubIDs: clubs)
    }
    private func memberships(_ ids: [Int], member: Int = 701) -> [TeamClubMembership] {
        ids.compactMap { TeamClubMembership(clubID: $0, memberID: member, status: "ACTIVE") }
    }
    private func team(members: [Int] = [701, 702], clubs: [Int] = [11, 22], formedBy: String = "INVITE") -> TeamRoster? {
        TeamRoster(teamID: 501, memberIDs: members, formedBy: formedBy, affiliatedClubIDs: clubs)
    }
    func testTeamMultiClubAuthorityRequiresActorAndAffiliatedClubs() throws {
        let eligible = try XCTUnwrap(TeamClubEligibilityProjection.evaluate(
            selection: selection(), actorMemberID: 701, actorClubs: memberships([11, 22]), team: team()))
        XCTAssertTrue(eligible.isEligible)
        XCTAssertEqual(eligible.reasonCode, "TEAM_ELIGIBLE")
        XCTAssertEqual(eligible.satisfiedClubIDs, [11, 22])
    }
    func testMissingTeamOrForeignMemberIsNotEligible() {
        XCTAssertEqual(TeamClubEligibilityProjection.evaluate(
            selection: selection(), actorMemberID: 701, actorClubs: memberships([11, 22]), team: nil)?.reasonCode,
                       "TEAM_REQUIRED")
        XCTAssertEqual(TeamClubEligibilityProjection.evaluate(
            selection: selection(), actorMemberID: 701, actorClubs: memberships([11, 22]),
            team: team(members: [702, 703]))?.reasonCode, "TEAM_REQUIRED")
    }
    func testCancelledRandomMatchmakingCannotMintATeam() {
        XCTAssertTrue(TeamClubEligibilityProjection.rejectsCancelledMatchmaking("RANDOM_MATCH"))
        XCTAssertTrue(TeamClubEligibilityProjection.rejectsCancelledMatchmaking("MATCHMAKING"))
        XCTAssertNil(team(formedBy: "RANDOM_MATCH"))
        XCTAssertNil(team(formedBy: "MATCHMAKING"))
        XCTAssertNotNil(team(formedBy: "CLUB"))
    }
    func testMultiClubFailsClosedWhenOneClubIsMissing() {
        let missingActor = TeamClubEligibilityProjection.evaluate(
            selection: selection(), actorMemberID: 701, actorClubs: memberships([11]), team: team())
        XCTAssertEqual(missingActor?.isEligible, false)
        XCTAssertEqual(missingActor?.reasonCode, "MULTI_CLUB_UNSATISFIED")
        XCTAssertEqual(missingActor?.satisfiedClubIDs, [11])
        let missingTeamClub = TeamClubEligibilityProjection.evaluate(
            selection: selection(), actorMemberID: 701, actorClubs: memberships([11, 22]),
            team: team(clubs: [11]))
        XCTAssertEqual(missingTeamClub?.reasonCode, "MULTI_CLUB_UNSATISFIED")
    }
    func testGrowthPersonalRankNeverGrantsTeamOrClubEligibility() {
        XCTAssertFalse(TeamClubEligibilityProjection.growthRankGrantsEligibility(1))
        XCTAssertFalse(TeamClubEligibilityProjection.growthRankGrantsEligibility(99))
        XCTAssertFalse(TeamClubEligibilityProjection.growthRankGrantsEligibility(nil))
        let withoutClubs = TeamClubEligibilityProjection.evaluate(
            selection: selection(), actorMemberID: 701, actorClubs: [], team: team(clubs: [11, 22]))
        XCTAssertEqual(withoutClubs?.isEligible, false)
        XCTAssertNotEqual(withoutClubs?.reasonCode, "TEAM_ELIGIBLE")
    }
    func testInactiveOrForeignMembershipsAreNotAuthority() {
        XCTAssertNil(TeamClubMembership(clubID: 11, memberID: 701, status: "PENDING"))
        XCTAssertNil(TeamClubMembership(clubID: 11, memberID: 701, status: "ACTIVE "))
        let foreign = [TeamClubMembership(clubID: 11, memberID: 888, status: "ACTIVE")!,
                       TeamClubMembership(clubID: 22, memberID: 888, status: "ACTIVE")!]
        XCTAssertNil(TeamClubEligibilityProjection.evaluate(
            selection: selection(), actorMemberID: 701, actorClubs: foreign, team: team()))
    }
    func testSoloStillRequiresEveryRequiredClubAndIgnoresGrowth() {
        let solo = selection(mode: "SOLO")
        let ok = TeamClubEligibilityProjection.evaluate(
            selection: solo, actorMemberID: 701, actorClubs: memberships([11, 22]), team: nil)
        XCTAssertEqual(ok?.reasonCode, "SOLO_ELIGIBLE")
        XCTAssertTrue(ok?.isEligible == true)
        XCTAssertEqual(TeamClubEligibilityProjection.evaluate(
            selection: solo, actorMemberID: 701, actorClubs: memberships([11]), team: nil)?.reasonCode,
                       "MULTI_CLUB_UNSATISFIED")
        XCTAssertFalse(TeamClubEligibilityProjection.growthRankGrantsEligibility(5))
    }
}
