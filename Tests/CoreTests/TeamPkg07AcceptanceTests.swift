import XCTest
@testable import QuestifyCore

/// Package 07 team acceptance: invite → detail/join review → result → return. Synthetic fixtures only;
/// a synthetic outcome is never production success and production writes stay closed.
@MainActor final class TeamPkg07AcceptanceTests: XCTestCase {
    private final class Box { var value: TeamSession?; init(_ v: TeamSession?) { value = v } }
    private func setup(_ scenario: TeamSyntheticService.Scenario) throws -> (TeamCoordinator, TeamSyntheticService, TeamMemoryJournal, Box) {
        let service = try TeamSyntheticService(scenario: scenario), journal = TeamMemoryJournal(), box = Box(try TeamSyntheticFixtures.session())
        return (TeamCoordinator(service: service, journal: journal, currentSession: { box.value }), service, journal, box)
    }

    func testFullAndEndedInvitationsOfferNoJoin() async throws {
        for (scenario, cta) in [(TeamSyntheticService.Scenario.invitationFull, TeamInvitationCTA.full), (.invitationEnded, .ended)] {
            let (c, service, _, _) = try setup(scenario)
            await c.loadDetail(.invitation("SYNTHETIC-TEAM"))
            let detail = try XCTUnwrap(c.detail)
            XCTAssertEqual(TeamPagePresentation.invitationCTA(detail), cta)
            XCTAssertNil(TeamPagePresentation.joinRouteCode(detail))
            c.prepare(.join(teamID: detail.team.id, inviteCode: "SYNTHETIC-TEAM"))
            XCTAssertNil(c.review, "closed team must not open a join review")
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }

    func testOpenInvitationReviewThenSyntheticResultAndReturnToDetailOnlyAfterFreshRead() async throws {
        let (c, service, journal, _) = try setup(.invitation)
        await c.loadDetail(.invitation("SYNTHETIC-TEAM"))
        XCTAssertEqual(TeamPagePresentation.invitationCTA(try XCTUnwrap(c.detail)), .join)
        c.prepare(.join(teamID: 4101, inviteCode: "SYNTHETIC-TEAM"))
        let review = try XCTUnwrap(c.review)
        XCTAssertTrue(service.submissions.isEmpty, "review is not a write")
        XCTAssertEqual(service.authority, .synthetic)
        await c.confirm(review)
        XCTAssertEqual(service.submissions, [review.id])
        XCTAssertEqual(c.writeState, .simulated); XCTAssertEqual(c.completedTeamID, 4101)
        XCTAssertTrue(journal.records.isEmpty)
    }

    func testRejectedJoinKeepsRetryAsFreshReviewAndNeverAutoResubmits() async throws {
        let (c, service, _, _) = try setup(.invitationRejected)
        await c.loadDetail(.invitation("SYNTHETIC-TEAM"))
        c.prepare(.join(teamID: 4101, inviteCode: "SYNTHETIC-TEAM"))
        await c.confirm(try XCTUnwrap(c.review))
        XCTAssertEqual(c.writeState, .rejected)
        XCTAssertTrue(TeamPagePresentation.showsJoinRetry(c.writeState, page: .invitation))
        XCTAssertFalse(TeamPagePresentation.showsJoinRetry(c.writeState, page: .detail))
        XCTAssertEqual(service.submissions.count, 1)
    }

    func testUnknownOutcomeIsNotRetryAndNotSuccess() async throws {
        let (c, service, _, _) = try setup(.unknownOutcome)
        await c.loadDetail(.invitation("SYNTHETIC-TEAM"))
        c.prepare(.join(teamID: 4101, inviteCode: "SYNTHETIC-TEAM"))
        await c.confirm(try XCTUnwrap(c.review))
        XCTAssertFalse(TeamPagePresentation.showsJoinRetry(c.writeState, page: .invitation))
        XCTAssertNotEqual(c.writeState, .acknowledged); XCTAssertNotEqual(c.writeState, .simulated)
        XCTAssertEqual(service.submissions.count, 1)
    }

    func testOldLinkAndMissingParametersFailClosed() throws {
        // Retired `?teamId=` share link.
        XCTAssertEqual(NativeNavigationContract.parseInternal("/pages/team/join/index?teamId=41"), .routeError(.legacyTeamLink))
        // Missing / empty / extra / duplicate parameters never produce an invitation.
        for text in ["/team/join", "/team/join?code=", "/team/join?code=%20", "/team/join?code=A&code=B",
                     "/team/join?code=A&x=1", "/team/join?code=A&fromTeamId=0", "/pages/team/join/index",
                     "/pages/team/join/index?code=A&teamId=4", "/pages/team/join/index?teamId=0"] {
            XCTAssertNil(NativeNavigationContract.parseInternal(text), text)
        }
        guard case .teamInvitation(let route)? = NativeNavigationContract.parseInternal("/team/join?code=ABC&fromTeamId=7") else { return XCTFail() }
        XCTAssertEqual(route.code, "ABC"); XCTAssertEqual(route.fromTeamID, 7)
        let state = TeamPagePresentation.blockingState(kind: .invitation, messageKey: "team.invalidLink", hasDetail: false, legacyTeamID: true)
        XCTAssertEqual(state?.kind, .legacyLink)
    }

    func testForbiddenAndNetworkReadsAreDistinctBlockingStates() async throws {
        for (scenario, kind) in [(TeamSyntheticService.Scenario.forbidden, TeamPageState.Kind.noPermission), (.networkFailure, .network)] {
            let (c, _, _, _) = try setup(scenario)
            await c.loadDetail(.invitation("SYNTHETIC-TEAM"))
            XCTAssertNil(c.detail)
            let state = TeamPagePresentation.blockingState(kind: .invitation, messageKey: c.messageKey, hasDetail: false, failure: c.readFailure)
            XCTAssertEqual(state?.kind, kind)
        }
    }

    func testAccountSwitchDropsInvitationSnapshotAndReview() async throws {
        let (c, service, _, box) = try setup(.invitation)
        await c.loadDetail(.invitation("SYNTHETIC-TEAM"))
        c.prepare(.join(teamID: 4101, inviteCode: "SYNTHETIC-TEAM"))
        let review = try XCTUnwrap(c.review)
        box.value = try TeamSyntheticFixtures.session(epoch: 2, accountID: 903)
        await c.confirm(review)
        XCTAssertTrue(service.submissions.isEmpty, "a review from the previous account must not submit")
        box.value = nil
        c.synchronizeSession()
        XCTAssertNil(c.review); XCTAssertNil(c.detail)
    }
}
