import XCTest

/// Offline fixtures only. Authored here; requires Apple simulator execution after integration.
final class TeamFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", destination: String = "list", chinese: Bool = false, accessible: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "teams", "--uitesting-team-scenario", scenario, "--uitesting-team-destination", destination]
        if accessible { app.launchArguments += ["--uitesting-large-text", "--uitesting-dark", "--uitesting-reduce-motion"] }
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
    private func assertSimulationCompleted() {
        let message = app.staticTexts["team.message"]
        for _ in 0..<12 { if message.exists && message.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(message.exists, app.debugDescription)
        XCTAssertTrue(message.label.contains("Offline simulation completed. No real team, ticket or invitation changed."), app.debugDescription)
        XCTAssertFalse(app.buttons["team.review.confirm"].exists)
    }
    private func reviewLeave() {
        let button = app.buttons["team.leave"]; reveal(button); button.tap()
        XCTAssertTrue(app.buttons["team.review.confirm"].waitForExistence(timeout: 5))
    }
    func testOwnedListDetailBackAndReopen() {
        launch(); let row = app.buttons["team.row.4101"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.navigationBars["Team details"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Synthetic teammate"])
        app.navigationBars["Team details"].buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.navigationBars["Team details"].waitForExistence(timeout: 5))
    }
    func testInvitationPreviewCloseLeavesTeamUntouched() {
        launch(destination: "detail"); let button = app.buttons["team.invitePreview"]; reveal(button); button.tap()
        XCTAssertTrue(app.staticTexts["team.invite.code"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send"].exists); XCTAssertFalse(app.buttons["Share"].exists)
        app.buttons["team.invite.close"].tap()
        XCTAssertTrue(app.navigationBars["Team details"].waitForExistence(timeout: 5))
    }
    func testCancelLeaveThenReopenReview() {
        launch(destination: "detail"); reviewLeave()
        reveal(app.buttons["team.review.cancel"]); app.buttons["team.review.cancel"].tap()
        XCTAssertTrue(app.navigationBars["Team details"].waitForExistence(timeout: 5))
        reviewLeave(); reveal(app.buttons["team.review.confirm"]); app.buttons["team.review.confirm"].tap()
        assertSimulationCompleted()
    }
    func testInvitationJoinReviewAndSimulation() {
        launch("invitation", destination: "invitation")
        let join = app.buttons["team.join"]; reveal(join); join.tap()
        reveal(app.buttons["team.review.confirm"]); app.buttons["team.review.confirm"].tap()
        assertSimulationCompleted()
        XCTAssertFalse(app.buttons["Purchase"].exists)
    }
    func testUnknownOutcomeCannotReplayAfterSameAccountReauthentication() {
        launch("unknownOutcome", destination: "detail"); reviewLeave()
        reveal(app.buttons["team.review.confirm"]); app.buttons["team.review.confirm"].tap()
        let check = app.buttons["team.checkOutcome"]; reveal(check)
        XCTAssertFalse(app.buttons["team.leave"].isEnabled)
        app.buttons["team.fixture.account"].tap(); reveal(check)
        XCTAssertFalse(app.buttons["team.leave"].isEnabled)
        check.tap(); XCTAssertFalse(app.buttons["team.leave"].isEnabled)
    }
    func testSignOutClosesPrivateDetailAndReview() {
        launch(destination: "detail")
        XCTAssertTrue(app.descendants(matching: .any)["team.detail.card"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["team.fixture.guest"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to view your teams"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic teammate"].exists)
        XCTAssertFalse(app.buttons["team.leave"].exists)
        app.buttons["team.fixture.account"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["team.detail.card"].firstMatch.waitForExistence(timeout: 5))
    }
    func testUnknownStatusHasNoMembershipActions() {
        launch("unknownStatus", destination: "detail")
        XCTAssertTrue(app.staticTexts["Status not provided"].waitForExistence(timeout: 10))
        app.swipeUp(); app.swipeUp()
        XCTAssertFalse(app.buttons["team.leave"].exists); XCTAssertFalse(app.buttons["team.disband"].exists)
        XCTAssertFalse(app.buttons["team.remove.902"].exists)
    }
    func testInProgressFullEndedAndDisbandedRemainDistinct() {
        for (scenario, label) in [("inProgress", "In progress"), ("full", "Full"), ("ended", "Ended"), ("disbanded", "Disbanded")] {
            launch(scenario, destination: "detail")
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 10)); app.terminate()
        }
    }
    func testCreatePrivateTeamReviewCancelPreservesForm() {
        launch(destination: "create")
        let toggle = app.switches["team.create.inviteOnly"]; reveal(toggle)
        let nativeSwitch = toggle.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() }
        else { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, app.debugDescription)
        let review = app.buttons["team.create.review"]; reveal(review); review.tap()
        reveal(app.buttons["team.review.cancel"]); app.buttons["team.review.cancel"].tap()
        XCTAssertEqual(toggle.value as? String, "1")
        reveal(review); review.tap(); reveal(app.buttons["team.review.confirm"]); app.buttons["team.review.confirm"].tap()
        assertSimulationCompleted()
    }
    func testMissingInviteShowsRecoverableInvalidLinkState() {
        launch(destination: "missing")
        XCTAssertTrue(app.staticTexts["This team link is incomplete. Open a complete invitation or return to your teams."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["team.join"].exists); XCTAssertFalse(app.buttons["team.refresh"].exists)
    }
    func testReadFailureRetryAndEmptyStateAreDistinct() {
        launch("retry"); let refresh = app.buttons["team.refresh"]
        reveal(refresh); refresh.tap(); XCTAssertTrue(app.buttons["team.row.4101"].waitForExistence(timeout: 5))
        app.terminate(); launch("empty")
        XCTAssertTrue(app.staticTexts["No teams yet"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["team.row.4101"].exists)
    }
    func testChineseLargeTextDarkModeReviewAndCancelRemainReachable() {
        launch(destination: "detail", chinese: true, accessible: true)
        reviewLeave(); reveal(app.buttons["team.review.cancel"]); app.buttons["team.review.cancel"].tap()
        XCTAssertTrue(app.navigationBars["队伍详情"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Synthetic teams Chinese large text"; screenshot.lifetime = .deleteOnSuccess; add(screenshot)
    }
}
