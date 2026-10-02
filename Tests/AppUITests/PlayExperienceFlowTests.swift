import XCTest

final class PlayExperienceFlowTests: XCTestCase {
    private func launch(_ scenario: String = "classic", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-module", "playExperience", "--uitesting-play-experience-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 { if element.exists && element.isHittable { return }; app.swipeUp() }
    }
    func testClassicReviewCancelDoesNotCompleteTask() {
        let app = launch(); let node = app.buttons["playx.node.701"]
        XCTAssertTrue(node.waitForExistence(timeout: 5)); node.tap()
        let field = app.textFields["playx.answer.field"].exists ? app.textFields["playx.answer.field"] : app.textViews["playx.answer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3)); field.tap(); field.typeText("Synthetic answer")
        let review = app.buttons["playx.answer.review"]; reveal(review, app: app); review.tap()
        app.buttons["Cancel"].tap(); XCTAssertTrue(review.exists)
    }
    func testBranchDoesNotRevealHiddenTask() {
        let app = launch("branch"); XCTAssertTrue(app.buttons["playx.node.701"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["playx.node.702"].exists); XCTAssertFalse(app.staticTexts["Hidden synthetic node"].exists)
    }
    func testDormantEnvironmentShowsNoDevicePermissionPrompt() {
        let app = launch("disabled"); XCTAssertTrue(app.staticTexts["playx.disabled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["playx.node.701"].exists); XCTAssertEqual(app.alerts.count, 0)
    }
    func testMode2ShowsSeparateVerificationStep() {
        let app = launch("mode2"); let node = app.buttons["playx.node.701"]
        XCTAssertTrue(node.waitForExistence(timeout: 5)); node.tap()
        XCTAssertTrue(app.staticTexts["Three on-site steps"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["playx.answer.review"].exists)
    }
    func testEmptyEndingIsNotReportedAsFailure() {
        let app = launch(); let load = app.buttons["playx.results.load"]; reveal(load, app: app); XCTAssertTrue(load.exists); load.tap()
        let empty = app.staticTexts["playx.ending.empty"]; reveal(empty, app: app); XCTAssertTrue(empty.exists)
    }
    func testStopwatchStartsAndStopsLocally() {
        let app = launch(); let link = app.buttons["Stopwatch challenge"]; reveal(link, app: app); XCTAssertTrue(link.exists); link.tap()
        let toggle = app.buttons["playx.stopwatch.toggle"]; XCTAssertTrue(toggle.waitForExistence(timeout: 3)); toggle.tap(); toggle.tap()
        XCTAssertTrue(app.staticTexts["Completed rounds"].exists)
    }
    func testChineseJourneyLabels() {
        let app = launch(language: "zh-Hans"); XCTAssertTrue(app.buttons["playx.node.701"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["旅程游玩"].exists)
    }
}
