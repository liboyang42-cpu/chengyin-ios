import XCTest

/// Synthetic scenarios only. Runtime, VoiceOver and provider behavior require Apple execution.
final class PlayRouteMapContinuationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "routeMap", chinese: Bool = false, maximum: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playExperience",
            "--uitesting-play-experience-scenario", scenario, "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
            "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        if maximum { app.launchArguments += ["--uitesting-max-text", "--uitesting-dark"] }
        app.launch()
        if maximum { assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility5") }
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        XCTAssertTrue(button.isEnabled, app.debugDescription); button.tap()
    }
    private func openMap() {
        tap("playRoute.open")
        XCTAssertTrue(app.descendants(matching: .any)["playRoute.screen"].waitForExistence(timeout: 5), app.debugDescription)
    }
    private func backFromTask() { app.navigationBars.buttons.firstMatch.tap() }
    private func fixtureAction(_ id: String) { tap("playRoute.fixture.controls"); tap(id) }




    func testAccountChangeBackReopenAndRelaunchDoNotRestoreOldSelection() {
        launch(); openMap(); tap("playRoute.openCurrent"); fixtureAction("playRoute.fixture.account")
        XCTAssertTrue(app.navigationBars["Journey runtime"].waitForExistence(timeout: 5), app.debugDescription)
        openMap(); XCTAssertTrue(app.staticTexts["Synthetic second-account stop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic current stop"].exists)
        tap("playRoute.back"); openMap()
        XCTAssertTrue(app.navigationBars["Route map"].exists); XCTAssertFalse(app.navigationBars["Journey task"].exists)
        app.terminate(); launch(); openMap()
        XCTAssertTrue(app.staticTexts["Synthetic current stop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic second-account stop"].exists)
    }
    func testChineseMaximumTextUsesFullListAndExplicitRouteDisclaimer() {
        launch(chinese: true, maximum: true); openMap()
        XCTAssertTrue(app.navigationBars["路线地图"].waitForExistence(timeout: 5))
        let explanation = app.staticTexts["playRoute.explanation"]
        XCTAssertTrue(explanation.exists)
        XCTAssertTrue(explanation.label.contains("不代表可步行路线"))
        tap("playRoute.toggleMap"); tap("playRoute.stop.701")
        XCTAssertTrue(app.navigationBars["旅程任务"].waitForExistence(timeout: 5))
        backFromTask(); tap("playRoute.back")
        XCTAssertTrue(app.navigationBars["旅程游玩"].waitForExistence(timeout: 5))
        attachFixtureScreenshot(self, app: app, name: "Chinese maximum-text route navigation")
    }
    func testFreeExplorationDoesNotGainOrientationMapEntry() {
        launch("mode2")
        XCTAssertTrue(app.buttons["playFree.pack.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["playRoute.open"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["playRoute.screen"].exists)
    }
    func testExistingTaskReviewAndCancelStayOnTaskWhenOpenedFromMap() {
        launch("routeMapReview"); openMap(); tap("playRoute.openCurrent")
        let field = app.descendants(matching: .any).matching(identifier: "playx.answer.field").firstMatch
        XCTAssertTrue(revealFixtureElement(field, in: app), app.debugDescription)
        field.tap(); field.typeText("Synthetic answer")
        tap("playx.answer.review")
        XCTAssertTrue(app.buttons["playx.confirm"].waitForExistence(timeout: 5), app.debugDescription)
        let cancel = app.buttons["Cancel"]
        if cancel.exists && cancel.isHittable { cancel.tap() }
        else { dismissFixtureConfirmationPopover(in: app) }
        XCTAssertTrue(app.navigationBars["Journey task"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Synthetic answer")
        XCTAssertFalse(app.buttons["playx.confirm"].exists)
        backFromTask(); XCTAssertTrue(app.navigationBars["Route map"].waitForExistence(timeout: 5))
    }

}
