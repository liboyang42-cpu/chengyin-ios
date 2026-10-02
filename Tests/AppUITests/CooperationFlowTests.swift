import XCTest

/// Synthetic fixtures only; integrate module key cooperation -> CooperationFixtureHostView.
final class CooperationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "cooperation", "--uitesting-cooperation-scenario", scenario]
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
    func testInvitationFreshDetailBackReopenAndDirectionIsolation() {
        launch()
        let received = app.buttons["cooperation.invite.received.71.0"]
        XCTAssertTrue(received.waitForExistence(timeout: 10)); received.tap()
        XCTAssertTrue(app.navigationBars["Invitation details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample receiving partner"].exists)
        reveal(app.staticTexts["Sample recorded reply"])
        XCTAssertFalse(app.buttons["Accept"].exists)
        XCTAssertFalse(app.buttons["Pay"].exists)
        app.navigationBars["Invitation details"].buttons.firstMatch.tap()
        XCTAssertTrue(received.waitForExistence(timeout: 5)); received.tap()
        XCTAssertTrue(app.staticTexts["Sample receiving partner"].waitForExistence(timeout: 5))
        app.navigationBars["Invitation details"].buttons.firstMatch.tap()
        app.segmentedControls["cooperation.direction"].buttons["Sent"].tap()
        let sent = app.buttons["cooperation.invite.sent.71.0"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5)); sent.tap()
        XCTAssertTrue(app.staticTexts["Sample sent merchant"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample receiving partner"].exists)
    }
    func testPartialInboxKeepsOtherSourcesAndDoesNotClaimFullEmpty() {
        launch("partial")
        XCTAssertTrue(app.staticTexts["Some cooperation sources could not be loaded"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["cooperation.invite.received.71.0"].exists)
        reveal(app.staticTexts["Sample applying club"])
        reveal(app.staticTexts["Sample candidate source unavailable"])
        XCTAssertFalse(app.staticTexts["No received merchant registrations"].exists)
    }
    func testPoolClubGateAndCandidatePermissionAreNotEmptyOrRetryFailures() {
        launch("noClub")
        XCTAssertTrue(app.staticTexts["Create a club before using the cooperation pool"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No open cooperation topics"].exists)
        app.terminate(); launch("forbidden")
        XCTAssertTrue(app.staticTexts["You do not have access to this directory"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["仅主题发布者可查看候选池"].exists)
        XCTAssertFalse(app.buttons["cooperation.retry"].exists)
    }
    func testPoolKnownAndUnknownStatesAndOwnedCandidateDirectory() {
        launch()
        let pool = app.buttons["cooperation.pool.open"]
        XCTAssertTrue(pool.waitForExistence(timeout: 10)); pool.tap()
        XCTAssertTrue(app.staticTexts["Sample available collaboration"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Sample converted collaboration"])
        XCTAssertTrue(app.staticTexts["Approved · invitation created"].exists)
        reveal(app.staticTexts["Sample future pool state"])
        XCTAssertTrue(app.staticTexts["Status not confirmed"].exists)
        app.navigationBars["Cooperation pool"].buttons.firstMatch.tap()
        let candidates = app.buttons["cooperation.candidates.301"].firstMatch
        reveal(candidates); candidates.tap()
        XCTAssertTrue(app.staticTexts["Sample candidate club"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample candidate merchant"].exists)
        XCTAssertFalse(app.buttons["Confirm candidate"].exists)
    }
    func testFreshDetailReplacesStaleSnapshotAndSignOutHidesPrivateContent() {
        launch("refreshed")
        XCTAssertTrue(app.staticTexts["Sample receiving partner"].waitForExistence(timeout: 10))
        app.buttons["cooperation.refresh"].tap()
        XCTAssertTrue(app.staticTexts["Sample updated partner"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample receiving partner"].exists)
        app.terminate(); launch("sessionChange")
        let row = app.buttons["cooperation.invite.received.71.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.staticTexts["Sample receiving partner"].waitForExistence(timeout: 5))
        app.buttons["cooperation.fixture.signOut"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to view your cooperation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample receiving partner"].exists)
        XCTAssertFalse(app.staticTexts["Sample recorded reply"].exists)
    }
    func testEmptyGuestFailureUnavailableAndChineseStates() {
        for (scenario, text) in [("empty", "No invitations in this direction"), ("guest", "Sign in to view your cooperation"), ("failure", "Cooperation could not be loaded"), ("unconfigured", "Cooperation service is not configured"), ("unavailable", "This invitation is no longer in this list")] {
            launch(scenario)
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10), scenario)
            app.terminate()
        }
        launch("guest", chinese: true)
        XCTAssertTrue(app.staticTexts["登录后查看我的合作"].waitForExistence(timeout: 10))
    }
}
