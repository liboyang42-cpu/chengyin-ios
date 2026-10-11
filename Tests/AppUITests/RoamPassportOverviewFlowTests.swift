import XCTest

final class RoamPassportOverviewFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String = "content") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", scenario,
            "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let target = app.buttons[id]; XCTAssertTrue(revealFixtureElement(target, in: app)); target.tap()
    }
    func testOverviewShowsPartialLocalFactsAndExistingHistoryRoundTrip() {
        let app = app()
        XCTAssertTrue(element("roam.passport.trips", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("roam.passport.shops", app).exists)
        XCTAssertTrue(element("roam.passport.days", app).exists)
        XCTAssertTrue(element("roam.passport.distance", app).exists)
        XCTAssertTrue(revealFixtureElement(element("roam.passport.partial", app), in: app, requiresHittable: false))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "1/2")).firstMatch.exists)
        tap("roam.experience.history.open", app)
        let record = app.buttons.matching(identifier: "roam.experience.history.record").firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        XCTAssertTrue(element("roam.experience.session", app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("roam.passport.trips", app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testSuccessfulEmptyHasFourZeroMetricsAndNoError() {
        let app = app("empty")
        XCTAssertTrue(element("roam.passport.empty", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("roam.passport.trips", app).exists)
        XCTAssertTrue(element("roam.passport.shops", app).exists)
        XCTAssertFalse(element("roam.passport.error", app).exists)
        XCTAssertFalse(element("roam.passport.partial", app).exists)
        tap("roam.experience.album.open", app)
        XCTAssertTrue(element("roam.experience.album.empty", app).waitForExistence(timeout: 5))
    }
    func testCorruptionShowsRetryNotEmptyOrInventedTotals() {
        let app = app("historyCorrupt")
        XCTAssertTrue(element("roam.passport.error", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("roam.passport.trips", app).exists)
        XCTAssertFalse(element("roam.passport.empty", app).exists)
        tap("roam.experience.retry", app)
        XCTAssertTrue(element("roam.passport.error", app).exists)
        XCTAssertFalse(element("roam.passport.trips", app).exists)
    }
    func testSignOutRemovesAllPrivateSummaryValues() {
        let app = app("sessionChange")
        XCTAssertTrue(element("roam.passport.trips", app).waitForExistence(timeout: 5))
        app.buttons["roam.experience.fixture.signOut"].tap()
        XCTAssertTrue(element("roam.passport.error", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("roam.passport.trips", app).exists)
        XCTAssertFalse(element("roam.passport.shops", app).exists)
        XCTAssertFalse(element("roam.passport.days", app).exists)
        XCTAssertFalse(element("roam.passport.empty", app).exists)
    }
}
