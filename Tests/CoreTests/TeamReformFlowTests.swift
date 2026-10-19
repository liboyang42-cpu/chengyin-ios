import XCTest
@testable import QuestifyCore

/// Dormant U02 / U04 / U05–U07 team flows over synthetic ports. Authored, not run on Linux.
@MainActor final class TeamReformFlowTests: XCTestCase {
    private let enabled = ReformWorldCapabilities.syntheticFixture([.friendMultiInvite, .teamFirstMeeting])

    func testFlowsStayClosedByDefault() async {
        let invite = TeamFriendInviteFlow(teamID: 4101, sender: TeamSyntheticFriendInviteSender())
        XCTAssertFalse(invite.available); await invite.open(); XCTAssertEqual(invite.phase, .closed)
        let meeting = TeamMeetingFlow(teamID: 4101, service: TeamSyntheticMeetingService())
        XCTAssertFalse(meeting.available); await meeting.open(); XCTAssertEqual(meeting.phase, .closed)
        XCTAssertFalse(TeamFriendInviteFlow(teamID: 4101, sender: nil, capabilities: enabled).available)
        XCTAssertEqual(meeting.handshakes, [.dynamicQR])
    }

    func testInviteRequiresServerLimitReviewAndReportsPartialResults() async throws {
        let sender = TeamSyntheticFriendInviteSender(scenario: .partial)
        let flow = TeamFriendInviteFlow(teamID: 4101, sender: sender, capabilities: enabled)
        await flow.open(); XCTAssertEqual(flow.phase, .ready); XCTAssertEqual(flow.batch?.maximum, 3)
        for friend in flow.friends.prefix(3) { flow.toggle(friend) }
        flow.toggle(flow.friends[3]); XCTAssertEqual(flow.issue, .overLimit); XCTAssertEqual(flow.batch?.selected.count, 3)
        await flow.send(); XCTAssertEqual(sender.sendCount, 0, "nothing is sent before review")
        flow.review(); XCTAssertEqual(flow.reviewed?.count, 3)
        await flow.send()
        let summary = try XCTUnwrap(flow.batch?.summary)
        XCTAssertEqual(summary.sent, 1); XCTAssertEqual(summary.rejected, 1); XCTAssertEqual(summary.retryable, 1)
        let firstRequest = flow.batch?.requestIds["sf-3"]
        await flow.send() // retries only the failed recipient with the same request id
        XCTAssertEqual(sender.sendCount, 4); XCTAssertEqual(flow.batch?.requestIds["sf-3"], firstRequest)
        XCTAssertEqual(flow.batch?.summary.sent, 2); XCTAssertEqual(flow.batch?.summary.rejected, 1)
    }

    func testChangingSelectionInvalidatesReview() async {
        let flow = TeamFriendInviteFlow(teamID: 4101, sender: TeamSyntheticFriendInviteSender(), capabilities: enabled)
        await flow.open(); flow.toggle(flow.friends[0]); flow.review(); XCTAssertNotNil(flow.reviewed)
        flow.toggle(flow.friends[1]); XCTAssertNil(flow.reviewed)
        await flow.send(); XCTAssertNil(flow.batch?.deliveries["sf-1"])
    }

    func testUnknownDeliveryIsReadBackNotResent() async {
        let sender = TeamSyntheticFriendInviteSender(scenario: .unknown)
        let flow = TeamFriendInviteFlow(teamID: 4101, sender: sender, capabilities: enabled)
        await flow.open(); flow.toggle(flow.friends[0]); flow.review(); await flow.send()
        XCTAssertEqual(flow.batch?.summary.unknown, 1)
        await flow.send(); XCTAssertEqual(sender.sendCount, 1, "an unknown outcome is never resent")
        await flow.readBackUnknown()
        XCTAssertEqual(flow.batch?.deliveries["sf-1"], .sent(inviteId: "si-sf-1"))
    }

    func testRevokeWinsOverLateAcceptance() async {
        let flow = TeamFriendInviteFlow(teamID: 4101, sender: TeamSyntheticFriendInviteSender(), capabilities: enabled)
        await flow.open(); flow.toggle(flow.friends[0]); flow.review(); await flow.send()
        await flow.revoke(friendId: "sf-1")
        XCTAssertEqual(flow.batch?.deliveries["sf-1"], .revoked); XCTAssertEqual(flow.revokeStates["sf-1"]?.display, .revoked)
        flow.apply(friendId: "sf-1", kind: .accepted, serverVersion: 99, source: .lateResponse)
        XCTAssertEqual(flow.revokeStates["sf-1"]?.display, .revoked)
        XCTAssertEqual(flow.batch?.summary.revoked, 1)
    }

    func testUnknownRevokeIsNotShownAsRevoked() async {
        let sender = TeamSyntheticFriendInviteSender(); sender.revokeVersion = nil
        let flow = TeamFriendInviteFlow(teamID: 4101, sender: sender, capabilities: enabled)
        await flow.open(); flow.toggle(flow.friends[0]); flow.review(); await flow.send()
        await flow.revoke(friendId: "sf-1")
        XCTAssertTrue(flow.revokeUnknown.contains("sf-1"))
        XCTAssertEqual(flow.batch?.deliveries["sf-1"], .sent(inviteId: "si-sf-1"))
    }

    func testMeetingOnlyForServerConfirmedTeam() async {
        let flow = TeamMeetingFlow(teamID: 4101, service: TeamSyntheticMeetingService(scenario: .notEligible), capabilities: enabled)
        await flow.open(); XCTAssertEqual(flow.phase, .notEligible); XCTAssertNil(flow.meeting)
        XCTAssertFalse(RealNameScope.requiresRealName(.teamJoin))
    }

    func testRealNameGateIsServerDecided() async {
        let service = TeamSyntheticMeetingService(scenario: .realNameRequired)
        let flow = TeamMeetingFlow(teamID: 4101, service: service, capabilities: enabled)
        await flow.open(); XCTAssertEqual(flow.meeting?.phase, .realNameRequired)
        await flow.startHandshake(); XCTAssertEqual(flow.meeting?.phase, .realNameRequired)
        await flow.recheckRealName(); XCTAssertEqual(flow.meeting?.phase, .realNameRequired)
        service.realName = true
        await flow.recheckRealName(); XCTAssertEqual(flow.meeting?.phase, .readyToMeet)
    }

    func testHandshakeShowsOwnCodeAndServerDecides() async throws {
        let flow = TeamMeetingFlow(teamID: 4101, service: TeamSyntheticMeetingService(), capabilities: enabled)
        await flow.open(); await flow.startHandshake()
        XCTAssertEqual(flow.meeting?.phase, .handshaking)
        XCTAssertEqual(flow.myChallenge?.issuerMemberId, TeamSyntheticMeetingService.selfMember)
        XCTAssertFalse(flow.myCodeExpired())
        await flow.submitScanned(try TeamSyntheticMeetingService.peerChallenge())
        XCTAssertEqual(flow.meeting?.phase, .met)
    }

    func testWrongExpiredAndReplayedCodesAreRefused() async throws {
        let service = TeamSyntheticMeetingService(scenario: .rejectFirst)
        let flow = TeamMeetingFlow(teamID: 4101, service: service, capabilities: enabled)
        await flow.open(); await flow.startHandshake()
        await flow.submitScanned(try TeamSyntheticMeetingService.peerChallenge(teamID: 9999)); XCTAssertEqual(flow.scanIssue, .wrongCode)
        let old = Date().addingTimeInterval(-120)
        await flow.submitScanned(try TeamSyntheticMeetingService.peerChallenge(now: old)); XCTAssertEqual(flow.scanIssue, .expired)
        let code = try TeamSyntheticMeetingService.peerChallenge()
        await flow.submitScanned(code) // server rejects the first confirmation
        XCTAssertEqual(flow.meeting?.phase, .handshaking); XCTAssertEqual(flow.scanIssue, .wrongCode)
        await flow.submitScanned(code); XCTAssertEqual(flow.scanIssue, .replayed)
        XCTAssertEqual(service.confirmations.count, 1)
    }

    func testLostConfirmationIsReadBack() async throws {
        let service = TeamSyntheticMeetingService(scenario: .lostConfirmation)
        let flow = TeamMeetingFlow(teamID: 4101, service: service, capabilities: enabled)
        await flow.open(); await flow.startHandshake()
        await flow.submitScanned(try TeamSyntheticMeetingService.peerChallenge())
        XCTAssertEqual(flow.meeting?.phase, .confirmationPending); XCTAssertEqual(flow.scanIssue, .outcomeUnknown)
        await flow.readBackConfirmation(); XCTAssertEqual(flow.meeting?.phase, .met)
        XCTAssertEqual(service.confirmations.count, 1)
    }

    func testCancelIsFinalEvenAgainstLateVerification() async throws {
        let service = TeamSyntheticMeetingService(scenario: .lostConfirmation)
        let flow = TeamMeetingFlow(teamID: 4101, service: service, capabilities: enabled)
        await flow.open(); await flow.startHandshake()
        await flow.submitScanned(try TeamSyntheticMeetingService.peerChallenge())
        await flow.cancel(); XCTAssertEqual(flow.meeting?.phase, .cancelled); XCTAssertNil(flow.myChallenge)
        await flow.readBackConfirmation(); XCTAssertEqual(flow.meeting?.phase, .cancelled)
        XCTAssertFalse(flow.cancelUnknown)
    }

    func testOfferRulesUseFreshDetail() throws {
        func detail(_ status: Int, joined: Bool) throws -> TeamDetail {
            let json = #"{"team":{"id":4101,"title":"S","status":\#(status),"joinMode":2},"joined":\#(joined),"leader":false,"members":[]}"#
            return try JSONDecoder().decode(TeamDetail.self, from: Data(json.utf8))
        }
        XCTAssertTrue(TeamFriendInviteFlow.eligible(try detail(0, joined: true)))
        XCTAssertFalse(TeamFriendInviteFlow.eligible(try detail(0, joined: false)))
        XCTAssertFalse(TeamFriendInviteFlow.eligible(try detail(1, joined: true)))
        XCTAssertTrue(TeamMeetingFlow.mayOffer(try detail(1, joined: true)))
        XCTAssertTrue(TeamMeetingFlow.mayOffer(try detail(2, joined: true)))
        XCTAssertFalse(TeamMeetingFlow.mayOffer(try detail(0, joined: true)))
        XCTAssertFalse(TeamMeetingFlow.mayOffer(try detail(1, joined: false)))
        XCTAssertFalse(TeamMeetingFlow.mayOffer(nil))
    }
}
