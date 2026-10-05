import XCTest

/// Synthetic P057 UI scenarios only. These are authored, not Apple-run evidence.
final class ClubStoryFlowTests: XCTestCase {
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
    func testGroupedStopsHaveHoursAddressAndChapterMetadata() {
        launch()
        XCTAssertTrue(app.staticTexts["Lantern courtyard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["09:00–18:00"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic courtyard address"].exists)
        XCTAssertFalse(app.buttons["club.story.template.1"].exists)
        gameplay()
        XCTAssertTrue(app.buttons["club.story.template.1"].waitForExistence(timeout: 5))
    }
    func testChapterSwitchAndExpansionResetKeepEachPlayInItsOwnChapter() {
        launch(); gameplay(); tap("club.story.expand")
        XCTAssertEqual(app.buttons["club.story.expand"].label, "Collapse story")
        tap("club.story.chapter.1")
        XCTAssertFalse(app.staticTexts["Lantern puzzle"].exists)
        XCTAssertTrue(app.staticTexts["Library choices"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["club.story.expand"].label, "Read full story")
        tap("club.story.chapter.2")
        XCTAssertTrue(app.staticTexts["No gameplay in this chapter yet"].waitForExistence(timeout: 5))
        tap("club.story.chapter.0")
        XCTAssertTrue(app.staticTexts["Lantern puzzle"].waitForExistence(timeout: 5))
    }
    func testUnavailableAndInvalidSourcesDoNotOfferTemplateNavigation() {
        for scenario in ["unavailable", "invalid"] {
            launch(scenario); gameplay()
            XCTAssertTrue(app.staticTexts["club.story.templateUnavailable.1"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["club.story.template.1"].exists)
            if scenario == "invalid" { XCTAssertFalse(app.buttons["club.story.answer.1"].exists) }
            app.terminate()
        }
    }
    func testDuplicateChapterIDsKeepDisplaySelectableButAllRoutesDisabled() {
        launch("duplicateChapter"); gameplay(); tap("club.story.chapter.1")
        XCTAssertTrue(app.staticTexts["Library choices"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A separate synthetic chapter story."].exists)
        XCTAssertFalse(app.buttons["club.story.template.3"].exists)
        XCTAssertFalse(app.buttons["club.story.answer.3"].exists)
    }
    func testChineseRoutePlayAndEmptyChapterAreLocalized() {
        launch(language: "zh-Hans"); gameplay(); tap("club.story.chapter.2")
        XCTAssertTrue(app.staticTexts["这一章还没有玩法"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["club.story.noPlays"].exists)
    }
}
