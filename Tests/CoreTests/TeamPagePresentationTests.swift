import XCTest
@testable import QuestifyCore

/// Mini-program pages/team/detail and pages/team/join facts. Synthetic data only.
final class TeamPagePresentationTests: XCTestCase {
    private func detail(status: Int = 0, joined: Bool? = true, leader: Bool? = true, joinMode: Int = 2, code: String? = "SYNTHETIC-TEAM", expire: String? = "2030-05-02 10:00:00") throws -> TeamDetail {
        var team: [String: Any] = ["id": 4101, "title": "Synthetic", "status": status, "joinedCount": 2, "maxMembers": 4, "joinMode": joinMode]
        team["inviteCode"] = code; team["expireTime"] = expire
        var object: [String: Any] = ["team": team, "members": [["memberId": 901, "memberName": "A", "role": 1]]]
        object["joined"] = joined; object["leader"] = leader
        return try JSONDecoder().decode(TeamDetail.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testStatusChipAndModeHelpFollowSource() throws {
        XCTAssertTrue(TeamPagePresentation.statusIsLive(.recruiting)); XCTAssertTrue(TeamPagePresentation.statusIsLive(.full))
        for status in [TeamStatus.inProgress, .ended, .disbanded, .unknown] { XCTAssertFalse(TeamPagePresentation.statusIsLive(status)) }
        XCTAssertEqual(TeamPagePresentation.joinModeHelpKey(.publicApplication), "team.page.modeHelp.public")
        XCTAssertEqual(TeamPagePresentation.joinModeHelpKey(.invitation), "team.page.modeHelp.invitation")
        XCTAssertEqual(TeamPagePresentation.joinModeHelpKey(.unknown), "team.mode.unknown")
    }

    func testStartTextMatchesSourceFormatTime() {
        XCTAssertEqual(TeamPagePresentation.startText("2030-05-02 10:00:00", chinese: true), "5月2日 10:00")
        XCTAssertEqual(TeamPagePresentation.startText("2030-05-02 09:05", chinese: false), "May 2, 09:05")
        XCTAssertEqual(TeamPagePresentation.startText("2030/12/31 23:59", chinese: true), "12月31日 23:59")
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertEqual(TeamPagePresentation.startText("2030-05-02T02:00:00Z", chinese: true, displayZone: shanghai), "5月2日 10:00")
        XCTAssertEqual(TeamPagePresentation.startText("soon", chinese: true), "soon") // source shows unparseable text verbatim
        XCTAssertNil(TeamPagePresentation.startText("  ", chinese: true))
        XCTAssertNil(TeamPagePresentation.startText(nil, chinese: false))
    }

    func testDetailActionsMirrorWxml() throws {
        let leader = try detail()
        XCTAssertTrue(TeamPagePresentation.showsInviteEntry(leader))
        XCTAssertNil(TeamPagePresentation.joinRouteCode(leader))
        XCTAssertEqual(TeamPagePresentation.leaveLabelKey(leader), "team.page.leaveAndTransfer")
        XCTAssertTrue(TeamPagePresentation.showsRefundNote(leader))
        let visitor = try detail(joined: false, leader: false)
        XCTAssertEqual(TeamPagePresentation.joinRouteCode(visitor), "SYNTHETIC-TEAM")
        XCTAssertEqual(TeamPagePresentation.leaveLabelKey(visitor), "team.leave")
        XCTAssertFalse(TeamPagePresentation.showsRefundNote(visitor))
        // An omitted membership fact never offers a join; nor does a closed team or a missing code.
        XCTAssertNil(TeamPagePresentation.joinRouteCode(try detail(joined: nil, leader: nil)))
        XCTAssertNil(TeamPagePresentation.joinRouteCode(try detail(status: 1, joined: false, leader: false)))
        XCTAssertNil(TeamPagePresentation.joinRouteCode(try detail(joined: false, leader: false, code: nil)))
        XCTAssertFalse(TeamPagePresentation.showsInviteEntry(try detail(status: 2)))
    }

    func testInvitationCTAStates() throws {
        XCTAssertEqual(TeamPagePresentation.invitationCTA(try detail()), .openDetail)
        XCTAssertEqual(TeamPagePresentation.invitationCTA(try detail(joined: false, leader: false)), .join)
        XCTAssertEqual(TeamPagePresentation.invitationCTA(try detail(status: 1, joined: false, leader: false)), .full)
        for status in [2, 3, 4, 98] { XCTAssertEqual(TeamPagePresentation.invitationCTA(try detail(status: status, joined: false, leader: false)), .ended) }
        XCTAssertEqual(TeamInvitationCTA.full.key, "team.page.full"); XCTAssertEqual(TeamInvitationCTA.ended.key, "team.page.ended")
    }

    func testBlockingStatesForBothPages() {
        let missing = TeamPagePresentation.blockingState(kind: .detail, messageKey: "team.invalidLink", hasDetail: false)
        XCTAssertEqual(missing?.titleKey, "team.page.linkIncomplete"); XCTAssertEqual(missing?.action, .goBack)
        XCTAssertEqual(TeamPagePresentation.blockingState(kind: .invitation, messageKey: "team.invalidLink", hasDetail: false)?.titleKey, "team.page.inviteIncomplete")
        XCTAssertEqual(TeamPagePresentation.blockingState(kind: .invitation, messageKey: "team.invalidLink", hasDetail: false, legacyTeamID: true)?.kind, .legacyLink)
        XCTAssertEqual(TeamPagePresentation.blockingState(kind: .detail, messageKey: "team.signIn", hasDetail: false)?.action, .signIn)
        XCTAssertEqual(TeamPagePresentation.blockingState(kind: .invitation, messageKey: "team.signIn", hasDetail: false)?.titleKey, "team.page.signInInvite")
        XCTAssertEqual(TeamPagePresentation.blockingState(kind: .detail, messageKey: "team.loadFailed", hasDetail: false)?.action, .reload)
        XCTAssertEqual(TeamPagePresentation.blockingState(kind: .detail, messageKey: "team.unconfigured", hasDetail: false)?.actionKey, nil)
        // A retained snapshot never becomes a full-page error; it gets the stale banner instead.
        XCTAssertNil(TeamPagePresentation.blockingState(kind: .detail, messageKey: "team.refreshFailed", hasDetail: true))
        XCTAssertEqual(TeamPagePresentation.staleBanner(kind: .detail, messageKey: "team.refreshFailed", hasDetail: true)?.title, "team.page.teamStale")
        XCTAssertEqual(TeamPagePresentation.staleBanner(kind: .invitation, messageKey: "team.refreshFailed", hasDetail: true)?.title, "team.page.inviteStale")
        XCTAssertNil(TeamPagePresentation.staleBanner(kind: .detail, messageKey: nil, hasDetail: true))
        XCTAssertNil(TeamPagePresentation.blockingState(kind: .detail, messageKey: nil, hasDetail: false))
    }

    func testLoadingCopy() {
        XCTAssertEqual(TeamPagePresentation.loadingKey(.detail, hasDetail: false), "team.page.loadingDetail")
        XCTAssertEqual(TeamPagePresentation.loadingKey(.invitation, hasDetail: false), "team.page.readingInvite")
        XCTAssertEqual(TeamPagePresentation.loadingKey(.detail, hasDetail: true), "team.loading")
        XCTAssertEqual(TeamPagePresentation.loadingKey(.invitation, hasDetail: true), "team.page.checkingInvite")
    }
}
