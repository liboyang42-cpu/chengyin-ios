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
    func testOtherTeamRegisterRequestDoesNotRewriteOriginalRequestID() {
        let selection = selection()
        var ledger = TeamClubEligibilityLedger()
        let original = ledger.register(
            selection: selection, actorMemberID: 701, actorClubs: memberships([11, 22]),
            team: team(), originalRequestID: "reg-isol-01")
        XCTAssertEqual(original.originalRequestID, "reg-isol-01")
        XCTAssertEqual(original.outcome, "TEAM_ELIGIBLE")
        let rewrite = ledger.register(
            selection: selection, actorMemberID: 701, actorClubs: memberships([11, 22]),
            team: team(members: [701, 702, 703]), originalRequestID: "reg-isol-01")
        XCTAssertEqual(rewrite.outcome, EventScoreOriginalOutcome.idempotencyConflict.rawValue)
        XCTAssertEqual(rewrite.originalRequestID, "reg-isol-01")
        XCTAssertEqual(rewrite.registration?.memberIDs, [701, 702])
        let switched = ledger.register(
            selection: selection, actorMemberID: 701, actorClubs: memberships([11, 22]),
            team: team(members: [701, 702, 703]), originalRequestID: "reg-isol-02")
        XCTAssertEqual(switched.originalRequestID, "reg-isol-02")
        XCTAssertNotEqual(switched.originalRequestID, original.originalRequestID)
        XCTAssertEqual(ledger.readback("reg-isol-01").originalRequestID, "reg-isol-01")
        XCTAssertEqual(ledger.readback("reg-isol-01").registration?.memberIDs, [701, 702])
        XCTAssertEqual(ledger.recoverUnknown(originalRequestID: "reg-unknow").outcome,
                       EventScoreOriginalOutcome.notFound.rawValue)
        XCTAssertNil(ledger.recoverUnknown(originalRequestID: nil).originalRequestID)
        XCTAssertNil(ledger.recoverUnknown(originalRequestID: "").originalRequestID)
        XCTAssertEqual(ledger.recoverOriginal(originalRequestID: "reg-isol-01").originalRequestID, "reg-isol-01")
    }
    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyLedgerThenUniqueRegisterApplies() {
        let selection = selection()
        var ledger = TeamClubEligibilityLedger()
        let blank = ledger.recoverOriginal(originalRequestID: nil)
        XCTAssertNil(blank.originalRequestID)
        XCTAssertEqual(blank.outcome, EventScoreOriginalOutcome.notFound.rawValue)
        XCTAssertEqual(blank.mintedNewRequest, false)
        let neverReg = ledger.recoverOriginal(originalRequestID: "reg-orig-unk")
        XCTAssertEqual(neverReg.originalRequestID, "reg-orig-unk")
        XCTAssertEqual(neverReg.outcome, EventScoreOriginalOutcome.notFound.rawValue)
        XCTAssertNil(neverReg.registration)
        XCTAssertEqual(ledger.readback("reg-orig-unk").outcome, EventScoreOriginalOutcome.notFound.rawValue)
        let first = ledger.register(
            selection: selection, actorMemberID: 701, actorClubs: memberships([11, 22]),
            team: team(), originalRequestID: "reg-orig-unk")
        XCTAssertEqual(first.originalRequestID, "reg-orig-unk")
        XCTAssertEqual(first.outcome, "TEAM_ELIGIBLE")
        XCTAssertEqual(ledger.recoverOriginal(originalRequestID: "reg-orig-unk").outcome, "TEAM_ELIGIBLE")
        XCTAssertEqual(ledger.readback("reg-orig-unk").registration?.memberIDs, [701, 702])
    }
    func testUnusedIneligibleRegisterDoesNotOccupyThenUniqueRegisterApplies() {
        let selection = selection()
        var ledger = TeamClubEligibilityLedger()
        let unused = ledger.register(
            selection: selection, actorMemberID: 701, actorClubs: memberships([11, 22]),
            team: nil, originalRequestID: "c04-reg-inelig")
        XCTAssertEqual(unused.originalRequestID, "c04-reg-inelig")
        XCTAssertEqual(unused.outcome, "TEAM_REQUIRED")
        XCTAssertEqual(unused.mintedNewRequest, false)
        XCTAssertNil(unused.registration, "不合格报名观察不得占账")
        XCTAssertEqual(ledger.recoverOriginal(originalRequestID: "c04-reg-inelig").outcome,
                       EventScoreOriginalOutcome.notFound.rawValue)
        XCTAssertNil(ledger.readback("c04-reg-inelig").registration)
        let first = ledger.register(
            selection: selection, actorMemberID: 701, actorClubs: memberships([11, 22]),
            team: team(), originalRequestID: "c04-reg-inelig")
        XCTAssertEqual(first.originalRequestID, "c04-reg-inelig")
        XCTAssertEqual(first.outcome, "TEAM_ELIGIBLE")
        XCTAssertEqual(ledger.recoverOriginal(originalRequestID: "c04-reg-inelig").outcome, "TEAM_ELIGIBLE")
        XCTAssertEqual(ledger.readback("c04-reg-inelig").registration?.memberIDs, [701, 702])
    }
}
