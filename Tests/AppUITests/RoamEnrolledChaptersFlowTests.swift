import XCTest

final class RoamEnrolledChaptersFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String = "content", roam: String = "content") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", roam,
            "--uitesting-roam-chapters-scenario", scenario, "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        runningApp = app; app.launch()
        let open = app.buttons["roam.chapters.open"]; XCTAssertTrue(revealFixtureElement(open, in: app)); open.tap(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func testOrdinaryRoamTopicsOnlyCurrentRegistrationDetailAndBack() {
        let app = app(), row = app.buttons["roam.chapters.row.901"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); XCTAssertFalse(app.staticTexts["Sample activity ticket"].exists)
        row.tap(); XCTAssertTrue(element("ticketWallet.detail", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample exploration ticket"].exists)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["Sample pending chapter"], in: app))
        XCTAssertFalse(app.buttons["ticketWallet.play.open"].exists) // No fake play provider in offline host.
        app.navigationBars.buttons.element(boundBy: 0).tap(); XCTAssertTrue(row.waitForExistence(timeout: 5))
    }
    func testExpiredAndUnknownRowsHaveNoStartAction() {
        let app = app(); XCTAssertTrue(element("roam.chapters.status.902", app).waitForExistence(timeout: 10))
        XCTAssertTrue(revealFixtureElement(element("roam.chapters.status.903", app), in: app))
        XCTAssertFalse(app.buttons["roam.chapters.row.902"].exists); XCTAssertFalse(app.buttons["roam.chapters.row.903"].exists)
    }
    func testActivityPartialFailureStillShowsActualTopics() {
        let app = app("partial"); XCTAssertTrue(app.buttons["roam.chapters.row.901"].waitForExistence(timeout: 10))
        XCTAssertFalse(element("roam.chapters.error", app).exists)
    }
    func testEmptyAndReadFailureAreDistinctAndRetryIsReachable() {
        let empty = app("empty"); XCTAssertTrue(element("roam.chapters.empty", empty).waitForExistence(timeout: 10)); empty.terminate()
        let failed = app("failure"); XCTAssertTrue(element("roam.chapters.error", failed).waitForExistence(timeout: 10))
        XCTAssertFalse(element("roam.chapters.empty", failed).exists)
        let retry = failed.buttons["ticketWallet.retry"]; XCTAssertTrue(revealFixtureElement(retry, in: failed)); retry.tap()
        XCTAssertTrue(element("roam.chapters.error", failed).waitForExistence(timeout: 5))
    }
    func testSignOutClearsPrivateEnrolledTopicsAndDisablesEntry() {
        let app = app(roam: "sessionChange"); XCTAssertTrue(app.buttons["roam.chapters.row.901"].waitForExistence(timeout: 10))
        app.buttons["roam.experience.fixture.signOut"].tap(); XCTAssertFalse(app.staticTexts["Sample exploration ticket"].exists)
        XCTAssertTrue(app.buttons["roam.chapters.open"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["roam.chapters.open"].isEnabled)
    }
}
