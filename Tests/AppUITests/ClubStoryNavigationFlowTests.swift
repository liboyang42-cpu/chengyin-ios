import XCTest

/// Synthetic P057 UI scenarios only. These are authored, not Apple-run evidence.
final class ClubStoryNavigationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ scenario: String = "ready", language: String = "en") {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-club-governance", "--club-story-scenario", scenario,
            "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch(); tap("club.gov.openStory")
        XCTAssertTrue(app.segmentedControls["club.story.tabs"].waitForExistence(timeout: 5))
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        XCTAssertTrue(button.isHittable, app.debugDescription); button.tap()
    }
    private func gameplay() { app.segmentedControls["club.story.tabs"].buttons.element(boundBy: 1).tap() }
    private func back() { app.navigationBars.buttons.firstMatch.tap() }
    func testTemplateDetailUsesPersonalIDAndBackSupportsRepeatedSelection() {
        launch(); gameplay(); tap("club.story.template.1")
        XCTAssertTrue(app.staticTexts["Synthetic personal template 142"].waitForExistence(timeout: 5))
        back(); tap("club.story.template.1")
        XCTAssertTrue(app.staticTexts["Synthetic personal template 142"].waitForExistence(timeout: 5))
        back(); XCTAssertTrue(app.buttons["club.story.answer.1"].exists)
        XCTAssertFalse(app.buttons["club.story.answer.2"].exists)
    }
    func testSourceRefreshDropsOpenTemplateAndOldCards() {
        launch(); gameplay(); tap("club.story.template.1")
        XCTAssertTrue(app.staticTexts["Synthetic personal template 142"].waitForExistence(timeout: 5))
        tap("club.story.fixture.refresh")
        XCTAssertTrue(app.staticTexts["No chapters yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic personal template 142"].exists)
        XCTAssertFalse(app.buttons["club.story.template.1"].exists)
    }
    func testDelayedDetailCannotReappearAfterSourceRefresh() {
        launch("delayed"); gameplay(); tap("club.story.template.1")
        XCTAssertTrue(app.descendants(matching: .any)["memberTemplate.detail"].firstMatch.waitForExistence(timeout: 5))
        tap("club.story.fixture.refresh"); tap("club.story.fixture.finish")
        XCTAssertTrue(app.staticTexts["No chapters yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic personal template 142"].exists)
    }
    func testAccountAndReaderReplacementDismissOldDestination() {
        for control in ["club.story.fixture.account", "club.story.fixture.reader"] {
            launch(); gameplay(); tap("club.story.template.1")
            XCTAssertTrue(app.staticTexts["Synthetic personal template 142"].waitForExistence(timeout: 5))
            tap(control)
            let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Synthetic personal template 142"])
            XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 5), .completed)
            app.terminate()
        }
    }

}
