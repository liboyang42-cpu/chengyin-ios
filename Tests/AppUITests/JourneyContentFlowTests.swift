import XCTest
final class JourneyContentFlowTests: XCTestCase {
    private func launch(_ scenario: String = "default", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-module", "journeyContent", "--uitesting-journey-scenario", scenario,
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    private func tap(_ id: String, app: XCUIApplication) {
        let button = app.buttons[id]
        for _ in 0..<8 { if button.exists && button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
    }
    func testReviewCancelAndCloseLeaveMainTaskAvailable() {
        let app = launch(); tap("journey.check.roll", app: app)
        app.buttons["Cancel"].tap(); tap("journey.check.close", app: app)
        XCTAssertTrue(app.buttons["journey.fixture.mainTask"].exists)
    }
    func testRollRerollSettlementAndServerNarrative() {
        let app = launch(); tap("journey.check.roll", app: app); tap("journey.check.confirm", app: app)
        tap("journey.check.reroll", app: app); XCTAssertTrue(app.staticTexts["Reroll spends one luck. The server determines the outcome."].exists)
        app.buttons["Cancel"].tap(); tap("journey.check.settle", app: app); tap("journey.check.confirm", app: app)
        XCTAssertTrue(app.staticTexts["Synthetic server narrative"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["journey.check.reroll"].exists)
    }
    func testProbeFailureDoesNotBlockMainTask() {
        let app = launch("probeFailure")
        XCTAssertTrue(app.buttons["journey.fixture.mainTask"].waitForExistence(timeout: 3)); XCTAssertFalse(app.buttons["journey.check.roll"].exists)
    }
    func testUnknownOutcomeExposesOnlyReviewedRecovery() {
        let app = launch("unknown"); tap("journey.check.roll", app: app); tap("journey.check.confirm", app: app)
        XCTAssertTrue(app.buttons["journey.check.recover"].waitForExistence(timeout: 3)); XCTAssertFalse(app.buttons["journey.check.roll"].exists)
    }
    func testChineseAndDormantNoPermissions() {
        let app = launch("disabled", language: "zh-Hans")
        XCTAssertTrue(app.buttons["journey.fixture.mainTask"].waitForExistence(timeout: 3)); XCTAssertEqual(app.alerts.count, 0)
        XCTAssertTrue(app.navigationBars["旅程检定"].exists)
    }
}
