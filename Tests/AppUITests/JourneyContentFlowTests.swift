import XCTest
final class JourneyContentFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ scenario: String = "default", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "journeyContent", "--uitesting-journey-scenario", scenario,
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    private func tap(_ id: String, app: XCUIApplication) {
        let button = app.buttons[id]
        if id == "journey.check.cancelReview" {
            XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertTrue(button.isHittable)
        } else {
            if id == "journey.check.confirm" { XCTAssertTrue(button.waitForExistence(timeout: 5)) }
            XCTAssertTrue(revealFixtureElement(button, in: app, maximumSwipes: 15), app.debugDescription)
        }
        button.tap()
    }
    func testReviewCancelAndCloseLeaveMainTaskAvailable() {
        let app = launch(); tap("journey.check.roll", app: app)
        tap("journey.check.cancelReview", app: app); tap("journey.check.close", app: app)
        XCTAssertTrue(app.buttons["journey.fixture.mainTask"].exists)
    }
    func testRollRerollSettlementAndServerNarrative() {
        let app = launch(); tap("journey.check.roll", app: app); tap("journey.check.confirm", app: app)
        tap("journey.check.reroll", app: app); XCTAssertTrue(app.staticTexts["Reroll spends one luck. The server determines the outcome."].exists)
        tap("journey.check.cancelReview", app: app); tap("journey.check.settle", app: app); tap("journey.check.confirm", app: app)
        let narrative = app.staticTexts["Synthetic server narrative"]
        XCTAssertTrue(revealFixtureElement(narrative, in: app, towardTop: true, requiresHittable: false))
        XCTAssertTrue(narrative.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["journey.check.reroll"].exists)
    }
    func testProbeFailureDoesNotBlockMainTask() {
        let app = launch("probeFailure")
        XCTAssertTrue(app.buttons["journey.fixture.mainTask"].waitForExistence(timeout: 3)); XCTAssertFalse(app.buttons["journey.check.roll"].exists)
    }
    func testUnknownOutcomeExposesOnlyReviewedRecovery() {
        let app = launch("unknown"); tap("journey.check.roll", app: app); tap("journey.check.confirm", app: app)
        let recovery = app.buttons["journey.check.recover"]
        XCTAssertTrue(revealFixtureElement(recovery, in: app)); XCTAssertTrue(recovery.isEnabled)
        XCTAssertFalse(app.buttons["journey.check.roll"].exists)
        XCTAssertFalse(app.buttons["journey.check.reroll"].exists)
    }
    func testChineseAndDormantNoPermissions() {
        let app = launch("disabled", language: "zh-Hans")
        XCTAssertTrue(app.buttons["journey.fixture.mainTask"].waitForExistence(timeout: 3)); XCTAssertEqual(app.alerts.count, 0)
        XCTAssertTrue(app.navigationBars["旅程检定"].exists)
    }
}
