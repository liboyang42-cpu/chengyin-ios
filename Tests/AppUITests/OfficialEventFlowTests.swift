import XCTest

/// Synthetic UI tests. Requires ModuleFixture.officialEvents → OfficialFixtureHostView.
/// Authored only until run on an Apple simulator; no live account or network is used.
final class OfficialEventFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", destination: String = "browser", chinese: Bool = false, accessible: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "officialEvents", "--uitesting-official-scenario", scenario, "--uitesting-official-destination", destination]
        if accessible { app.launchArguments += ["--uitesting-large-text", "--uitesting-dark", "--uitesting-reduce-motion"] }
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<10 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
    private func select(_ title: String) {
        let picker = app.descendants(matching: .any)["official.filter"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        app.buttons[title].firstMatch.tap()
    }
    func testListDetailBackReopenAndStatusBuckets() {
        launch()
        let first = app.buttons["official.event.71"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        XCTAssertTrue(app.navigationBars["Official event details"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Price not provided by the source"])
        XCTAssertFalse(app.buttons["Sign up"].exists)
        app.navigationBars["Official event details"].buttons.firstMatch.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        XCTAssertTrue(app.navigationBars["Official event details"].waitForExistence(timeout: 5))
        app.navigationBars["Official event details"].buttons.firstMatch.tap()
        select("Upcoming")
        XCTAssertTrue(app.buttons["official.event.72"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["official.event.71"].exists)
        select("Ended")
        XCTAssertTrue(app.buttons["official.event.73"].waitForExistence(timeout: 5))
    }
    func testSearchIsLocalAndMineDoesNotRetainInvisibleFilter() {
        launch()
        let field = app.textFields["official.search"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("No synthetic match\n")
        XCTAssertTrue(app.staticTexts["No matching official events"].waitForExistence(timeout: 5))
        select("Joined")
        XCTAssertTrue(app.buttons["official.event.71"].waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists)
    }
    func testGuestCanBrowseButPrivateInboxRequiresLogin() {
        launch("guest")
        XCTAssertTrue(app.buttons["official.event.71"].waitForExistence(timeout: 10))
        app.buttons["official.more"].tap(); app.buttons["Invitations"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Sign in to view your official-event records"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["official.inbox.content"].exists)
    }
    func testPublisherDenialIsNotRetryableFailure() {
        launch("noPermission", destination: "published")
        XCTAssertTrue(app.staticTexts["Your account does not have official publishing permission"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["official.retry"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["official.published.content"].exists)
    }
    func testPublisherHistoryStatsBackAndNoWrites() {
        launch("content", destination: "published")
        let notice = app.buttons["official.broadcast.91"]
        reveal(notice); notice.tap()
        XCTAssertTrue(app.navigationBars["Broadcast statistics"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["unmappedMetric"])
        XCTAssertFalse(app.staticTexts["internalObject"].exists)
        XCTAssertFalse(app.buttons["Publish"].exists)
        app.navigationBars["Broadcast statistics"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["My published content"].waitForExistence(timeout: 5))
    }
    func testSignOutImmediatelyHidesPrivateInvitationsAndCanReenter() {
        launch("content", destination: "inbox")
        XCTAssertTrue(app.staticTexts["Synthetic organizer invitation"].waitForExistence(timeout: 10))
        app.buttons["official.fixture.guest"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to view your official-event records"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic organizer invitation"].exists)
        app.buttons["official.fixture.account"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic organizer invitation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Accept"].exists); XCTAssertFalse(app.buttons["Decline"].exists)
    }
    func testRetryRecoversWithoutStaleContent() {
        launch("retry")
        XCTAssertTrue(app.buttons["official.retry"].waitForExistence(timeout: 10))
        app.buttons["official.retry"].tap()
        XCTAssertTrue(app.buttons["official.event.71"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["official.retry"].exists)
    }
    func testUnknownFactsDoNotBecomeFreeOrAvailable() {
        launch("unknown", destination: "detail")
        XCTAssertTrue(app.staticTexts["Status not provided"].waitForExistence(timeout: 10))
        reveal(app.staticTexts["Price not provided by the source"])
        reveal(app.staticTexts["No rewards configured"])
        XCTAssertFalse(app.staticTexts["Free"].exists)
    }
    func testEmptyUnconfiguredAndUnavailableHaveDistinctCopy() {
        for (scenario, destination, text) in [("empty", "browser", "No official events in this category"), ("unconfigured", "browser", "Official-event service is not configured"), ("unavailable", "detail", "This record is unavailable for this account")] {
            launch(scenario, destination: destination)
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10), scenario)
            app.terminate()
        }
    }
    func testChineseAndLargeTextDarkReduceMotionSyntheticPresentation() {
        launch("guest", destination: "inbox", chinese: true, accessible: true)
        XCTAssertTrue(app.staticTexts["登录后查看我的官方活动记录"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Official invitation guest - Chinese large text dark reduced motion synthetic"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
