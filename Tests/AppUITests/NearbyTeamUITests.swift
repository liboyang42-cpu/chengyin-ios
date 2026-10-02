import XCTest

/// Requires the host's DEBUG-only `--nearby-team-fixture` branch. Never opens a live location/session.
final class NearbyTeamUITests: XCTestCase {
    private func launch(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--nearby-team-fixture", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    func testManualContextAndReviewCancellation() {
        let app = launch()
        XCTAssertTrue(app.textFields["nearby.latitude"].waitForExistence(timeout: 5))
        let apply = app.buttons["nearby.apply.501"]
        XCTAssertTrue(revealFixtureElement(apply, in: app), app.debugDescription)
        XCTAssertTrue(apply.isHittable); apply.tap()
        XCTAssertTrue(app.buttons["nearby.confirm"].waitForExistence(timeout: 3))
        app.buttons["nearby.cancel"].tap(); XCTAssertFalse(app.buttons["nearby.confirm"].exists)
        XCTAssertTrue(apply.exists)
    }
    func testSimulationUsesPendingStateAndNoLocationAlert() {
        let app = launch(); let apply = app.buttons["nearby.apply.501"]
        XCTAssertTrue(app.textFields["nearby.latitude"].waitForExistence(timeout: 5))
        XCTAssertTrue(revealFixtureElement(apply, in: app), app.debugDescription); apply.tap()
        app.buttons["nearby.confirm"].tap()
        XCTAssertTrue(app.buttons["nearby.withdraw.501"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testChineseLabelsAndMyApplications() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.segmentedControls["nearby.section"].waitForExistence(timeout: 5))
        app.segmentedControls["nearby.section"].buttons.element(boundBy: 1).tap()
        let withdraw = app.buttons["nearby.withdraw.502"]
        XCTAssertTrue(revealFixtureElement(withdraw, in: app), app.debugDescription)
        XCTAssertTrue(withdraw.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["nearby.mine.empty"].exists)
    }
}
