import XCTest

final class PlayExperienceFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ scenario: String = "classic", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playExperience", "--uitesting-play-experience-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        runningApp = app; app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription)
    }
    func testClassicReviewCancelDoesNotCompleteTask() {
        let app = launch(); let node = app.buttons["playx.node.701"]
        reveal(node, app: app); XCTAssertTrue(node.waitForExistence(timeout: 5)); node.tap()
        XCTAssertTrue(app.navigationBars["Journey task"].waitForExistence(timeout: 5), app.debugDescription)
        let field = app.descendants(matching: .any).matching(identifier: "playx.answer.field").firstMatch
        reveal(field, app: app); field.tap(); field.typeText("Synthetic answer")
        let review = app.buttons["playx.answer.review"]; reveal(review, app: app); review.tap()
        let cancel = app.buttons["Cancel"]
        if cancel.exists && cancel.isHittable { cancel.tap() }
        else {
            // Native confirmation popovers dismiss outside their bubble instead of rendering Cancel.
            XCTAssertTrue(app.buttons["playx.confirm"].waitForExistence(timeout: 3), app.debugDescription)
            dismissFixtureConfirmationPopover(in: app)
        }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.sheets["Review action"])
        let editable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: review)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed, editable], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(app.buttons["playx.confirm"].exists)
        XCTAssertEqual(field.value as? String, "Synthetic answer")
        attachFixtureScreenshot(self, app: app, name: "Classic review cancelled with answer retained")
    }
    func testBranchDoesNotRevealHiddenTask() {
        let app = launch("branch"); let node = app.buttons["playx.node.701"]
        reveal(node, app: app); XCTAssertTrue(node.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["playx.node.702"].exists); XCTAssertFalse(app.staticTexts["Hidden synthetic node"].exists)
    }
    func testDormantEnvironmentShowsNoDevicePermissionPrompt() {
        let app = launch("disabled"); XCTAssertTrue(app.staticTexts["playx.disabled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["playx.node.701"].exists); XCTAssertEqual(app.alerts.count, 0)
    }
    func testMode2ShowsSeparateVerificationStep() {
        let app = launch("mode2"); let node = app.buttons["playx.node.701"]
        reveal(node, app: app); XCTAssertTrue(node.waitForExistence(timeout: 5)); node.tap()
        XCTAssertTrue(app.navigationBars["Journey task"].waitForExistence(timeout: 5), app.debugDescription)
        let steps = app.staticTexts["Three on-site steps"]; reveal(steps, app: app)
        XCTAssertTrue(steps.exists, app.debugDescription)
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
        let app = launch(language: "zh-Hans"); let node = app.buttons["playx.node.701"]
        reveal(node, app: app); XCTAssertTrue(node.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["旅程游玩"].exists)
    }
}
