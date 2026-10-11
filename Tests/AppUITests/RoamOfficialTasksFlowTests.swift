import XCTest

final class RoamOfficialTasksFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String = "content", roam: String = "content") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", roam,
            "--uitesting-roam-tasks-scenario", scenario, "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        runningApp = app; app.launch()
        let open = app.buttons["roam.tasks.open"]; XCTAssertTrue(revealFixtureElement(open, in: app)); open.tap()
        return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func select(_ title: String, _ app: XCUIApplication) {
        let filter = element("roam.tasks.filter", app); XCTAssertTrue(revealFixtureElement(filter, in: app)); filter.tap()
        app.buttons.matching(identifier: title).firstMatch.tap()
    }
    func testOrdinaryRoamEntryOfficialDetailBackAndAllFourBuckets() {
        let app = app(), first = app.buttons["roam.tasks.event.71"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); XCTAssertTrue(revealFixtureElement(first, in: app)); first.tap()
        XCTAssertTrue(app.navigationBars["Official event details"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("official.detail.content", app).exists)
        XCTAssertFalse(app.buttons["Sign up"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        select("Upcoming", app); XCTAssertTrue(app.buttons["roam.tasks.event.72"].waitForExistence(timeout: 5))
        select("Ended", app); XCTAssertTrue(app.buttons["roam.tasks.event.73"].waitForExistence(timeout: 5))
        select("Joined", app); XCTAssertTrue(app.staticTexts["Synthetic joined event"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["roam.tasks.open"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testSourceKeywordHasRealNoResultsState() {
        let app = app(); XCTAssertTrue(app.buttons["roam.tasks.event.71"].waitForExistence(timeout: 10))
        let field = app.textFields["roam.tasks.search"]; field.tap(); field.typeText("no-match")
        XCTAssertTrue(element("roam.tasks.empty", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roam.tasks.event.71"].exists)
        XCTAssertFalse(element("roam.tasks.error", app).exists)
    }
    func testInitialReadFailureCanRetryEntireSnapshot() {
        let app = app("retry")
        XCTAssertTrue(element("roam.tasks.error", app).waitForExistence(timeout: 10))
        let retry = app.buttons["official.retry"]; XCTAssertTrue(revealFixtureElement(retry, in: app)); retry.tap()
        XCTAssertTrue(app.buttons["roam.tasks.event.71"].waitForExistence(timeout: 10))
        XCTAssertFalse(element("roam.tasks.error", app).exists)
    }
    func testEmptyIsNotUnconfiguredOrReadFailure() {
        let app = app("empty")
        XCTAssertTrue(element("roam.tasks.empty", app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("roam.tasks.error", app).exists)
        select("Joined", app)
        XCTAssertTrue(app.staticTexts["No joined official events"].waitForExistence(timeout: 5))
    }
    func testSignOutRetiresTasksAndPrivateParticipation() {
        let app = app(roam: "sessionChange")
        XCTAssertTrue(app.buttons["roam.tasks.event.71"].waitForExistence(timeout: 10))
        select("Joined", app); XCTAssertTrue(app.staticTexts["Synthetic joined event"].waitForExistence(timeout: 5))
        app.buttons["roam.experience.fixture.signOut"].tap()
        XCTAssertFalse(app.staticTexts["Synthetic joined event"].exists)
        XCTAssertFalse(app.buttons["roam.tasks.event.71"].exists)
        XCTAssertTrue(app.buttons["roam.tasks.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roam.tasks.open"].isEnabled)
    }
}
