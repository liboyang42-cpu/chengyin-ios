import XCTest

/// Mini-program pages/team/detail + pages/team/join parity and the dormant U02 / U05–U07 flows.
/// Offline fixtures only. Authored here; requires Apple simulator execution after integration.
final class TeamPageParityFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", destination: String = "detail", chinese: Bool = false, reform: String? = nil) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US",
                               "--uitesting-module", "teams", "--uitesting-team-scenario", scenario, "--uitesting-team-destination", destination]
        if let reform { app.launchArguments += ["--uitesting-team-reform", reform] }
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testLeaderDetailShowsSourceCopyInChinese() {
        launch(chinese: true)
        XCTAssertTrue(any("teamPage.subtitle").waitForExistence(timeout: 10))
        XCTAssertTrue(any("teamPage.subtitle").label.contains("组队与否不影响活动举行"), app.debugDescription)
        XCTAssertTrue(any("teamPage.meta").label.contains("5月2日 10:00"), app.debugDescription)
        let leave = app.buttons["team.leave"]; reveal(leave)
        XCTAssertEqual(leave.label, "退出并移交队长")
        reveal(app.staticTexts["退队不会退款；如需退票，请在订单中单独处理。"])
        XCTAssertTrue(app.staticTexts["只有拿到邀请链接的人能加入"].exists || app.staticTexts["陌生人可在附近队伍里申请加入"].exists)
        XCTAssertEqual(app.buttons["team.invitePreview"].label, "邀请队友")
    }

    func testNonmemberDetailRoutesToInvitationJoin() {
        launch("invitation")
        let route = app.buttons["teamPage.joinRoute"]; reveal(route); route.tap()
        XCTAssertTrue(app.navigationBars["Team invitation"].waitForExistence(timeout: 5))
        XCTAssertTrue(any("teamPage.inviteExplainer").waitForExistence(timeout: 5))
        reveal(app.buttons["team.join"])
        XCTAssertFalse(app.buttons["team.leave"].exists)
    }

    func testFullAndEndedInvitationsShowDisabledSourceCTA() {
        launch("invitationFull", destination: "invitation")
        let closed = app.buttons["teamPage.closedInvitation"]; reveal(closed)
        XCTAssertEqual(closed.label, "Team is full"); XCTAssertFalse(closed.isEnabled); XCTAssertFalse(app.buttons["team.join"].exists)
        app.terminate()
        launch("invitationEnded", destination: "invitation")
        reveal(app.buttons["teamPage.closedInvitation"])
        XCTAssertEqual(app.buttons["teamPage.closedInvitation"].label, "Team has ended")
    }

    func testIncompleteAndLegacyLinksShowStateShell() {
        launch(destination: "missing")
        XCTAssertTrue(app.staticTexts["teamPage.state.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["teamPage.state.title"].label, "Invitation link is incomplete")
        XCTAssertTrue(app.buttons["teamPage.state.action"].exists)
        app.terminate()
        launch(destination: "legacy", chinese: true)
        XCTAssertTrue(app.staticTexts["teamPage.state.title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["teamPage.state.title"].label, "邀请链接已升级")
    }

    func testReformEntriesHiddenWithoutFixtureSwitch() {
        launch()
        reveal(app.buttons["team.leave"])
        XCTAssertFalse(app.buttons["teamReform.invite.open"].exists)
        XCTAssertFalse(app.buttons["teamReform.meeting.open"].exists)
    }

    func testFriendInviteReviewPartialFailureAndRetry() {
        launch(reform: "partial,content")
        let open = app.buttons["teamReform.invite.open"]; reveal(open); open.tap()
        for id in ["sf-1", "sf-2", "sf-3"] { let row = app.buttons["teamReform.invite.friend.\(id)"]; reveal(row); row.tap() }
        let fourth = app.buttons["teamReform.invite.friend.sf-4"]; reveal(fourth); fourth.tap()
        reveal(app.staticTexts["You have reached the number the server allows for one invitation."])
        let review = app.buttons["teamReform.invite.reviewAction"]; reveal(review); review.tap()
        XCTAssertEqual(app.staticTexts["teamReform.invite.reviewCount"].label, "3")
        let send = app.buttons["teamReform.invite.send"]; reveal(send); send.tap()
        let retry = app.buttons["teamReform.invite.retryFailed"]; reveal(retry); retry.tap()
        XCTAssertTrue(app.buttons["teamReform.invite.revoke.sf-3"].waitForExistence(timeout: 5))
        let revoke = app.buttons["teamReform.invite.revoke.sf-1"]; reveal(revoke); revoke.tap()
        XCTAssertTrue(any("teamReform.invite.revoked.sf-1").waitForExistence(timeout: 5))
    }

    func testFriendInviteUnknownIsCheckedNotResent() {
        launch(reform: "unknown,content")
        let open = app.buttons["teamReform.invite.open"]; reveal(open); open.tap()
        let row = app.buttons["teamReform.invite.friend.sf-1"]; reveal(row); row.tap()
        app.buttons["teamReform.invite.reviewAction"].tap()
        let send = app.buttons["teamReform.invite.send"]; reveal(send); send.tap()
        XCTAssertFalse(app.buttons["teamReform.invite.retryFailed"].exists)
        let check = app.buttons["teamReform.invite.checkUnknown"]; reveal(check); check.tap()
        XCTAssertTrue(app.buttons["teamReform.invite.revoke.sf-1"].waitForExistence(timeout: 5))
    }

    func testMeetingHandshakeIsServerConfirmed() {
        launch("full", reform: "content,content")
        let open = app.buttons["teamReform.meeting.open"]; reveal(open); open.tap()
        let start = app.buttons["teamReform.meeting.start"]; reveal(start); start.tap()
        XCTAssertTrue(app.images["teamReform.meeting.code"].waitForExistence(timeout: 5))
        let scan = app.buttons["teamReform.meeting.simulateScan"]; reveal(scan); scan.tap()
        XCTAssertTrue(any("teamReform.meeting.met").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["teamReform.meeting.cancel"].exists)
    }

    func testMeetingRealNameOnlyInsideFlowAndCancelIsFinal() {
        launch("full", reform: "content,realNameRequired")
        let open = app.buttons["teamReform.meeting.open"]; reveal(open); open.tap()
        XCTAssertTrue(any("teamReform.meeting.realName").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["teamReform.meeting.start"].exists)
        let cancel = app.buttons["teamReform.meeting.cancel"]; reveal(cancel); cancel.tap()
        XCTAssertTrue(any("teamReform.meeting.cancelled").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["teamReform.meeting.recheckRealName"].exists)
    }

    func testMeetingNotOfferedWhileRecruiting() {
        launch(reform: "content,content")
        reveal(app.buttons["teamReform.invite.open"])
        XCTAssertFalse(app.buttons["teamReform.meeting.open"].exists)
    }
}
