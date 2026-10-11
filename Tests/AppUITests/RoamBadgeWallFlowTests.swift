import XCTest

final class RoamBadgeWallFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String = "success", roam: String = "content") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", roam,
            "--uitesting-roam-badges-scenario", scenario, "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        runningApp = app; app.launch()
        let open = app.buttons["roam.badgeWall.open"]; XCTAssertTrue(revealFixtureElement(open, in: app)); open.tap()
        return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func testRoamBadgeWallReadsExistingIdentityAndEarnedMedalDetailsThenReturns() {
        let app = app()
        let badge = app.buttons["profile.badge.medal.0"]
        XCTAssertTrue(revealFixtureElement(badge, in: app)); badge.tap()
        XCTAssertTrue(element("objects.badge.detail", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Fixture city medal"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let identity = app.buttons["profile.badge.identity.0"]
        XCTAssertTrue(revealFixtureElement(identity, in: app)); identity.tap()
        XCTAssertTrue(app.staticTexts["Fixture identity"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["roam.badgeWall.open"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testPartialWallKeepsIdentityAndDoesNotInventMedals() {
        let app = app("partial")
        XCTAssertTrue(app.buttons["profile.badge.identity.0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Synthetic medals unavailable"].exists)
        XCTAssertFalse(app.buttons["profile.badge.medal.0"].exists)
    }
    func testReadFailureUsesExistingRetryNotEmptyWall() {
        let app = app("error")
        XCTAssertTrue(element("profile.badges.error", app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["profile.badges.retry"].exists)
        app.buttons["profile.badges.retry"].tap()
        XCTAssertTrue(element("profile.badges.error", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["profile.badge.medal.0"].exists)
    }
    func testEmptyAndUnconfiguredRemainDistinct() {
        let empty = app("empty")
        XCTAssertTrue(empty.staticTexts["No badges yet"].waitForExistence(timeout: 10))
        XCTAssertFalse(element("profile.badges.error", empty).exists)
        empty.terminate()
        let unavailable = app("unconfigured")
        XCTAssertTrue(element("profile.badges.unavailable", unavailable).waitForExistence(timeout: 10))
        XCTAssertFalse(unavailable.staticTexts["No badges yet"].exists)
    }
    func testSignOutClosesPrivateBadgeDataAndDisablesRoamEntry() {
        let app = app(roam: "sessionChange")
        XCTAssertTrue(app.buttons["profile.badge.identity.0"].waitForExistence(timeout: 10))
        app.buttons["roam.experience.fixture.signOut"].tap()
        XCTAssertFalse(app.staticTexts["Fixture identity"].exists)
        XCTAssertTrue(app.buttons["roam.badgeWall.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roam.badgeWall.open"].isEnabled)
    }
}
