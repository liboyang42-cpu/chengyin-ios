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
        if ["club.story.chapter.0", "club.story.chapter.1", "club.story.chapter.2"].contains(id) {
            tapChapter(id); return
        }
        let button = app.buttons[id]
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        XCTAssertTrue(button.isHittable, app.debugDescription); button.tap()
    }
    private func tapChapter(_ id: String) {
        // These synthetic chapter controls live in a horizontal scroller. The
        // ordinary content helper scrolls vertically and cannot expose chapter 3.
        let scrollers = app.scrollViews.allElementsBoundByIndex.filter { $0.buttons[id].exists }
        guard scrollers.count == 1, let scroller = scrollers.first,
              revealFixtureElement(scroller, in: app, towardTop: true, requiresHittable: false) else {
            XCTFail("Expected one visible chapter selector. " + app.debugDescription); return
        }
        for attempt in 0...8 {
            let matches = scroller.buttons.matching(identifier: id)
            guard matches.count == 1 else { XCTFail("Chapter selector must stay unique. " + app.debugDescription); return }
            let button = matches.element(boundBy: 0)
            let visible = scroller.frame.intersection(app.frame)
            let frame = button.frame
            guard !visible.isEmpty, !visible.isNull, !frame.isEmpty else {
                XCTFail("Chapter selector needs real geometry. " + app.debugDescription); return
            }
            if visible.contains(frame), button.isEnabled, button.isHittable {
                button.tap(); return
            }
            guard attempt < 8 else { break }
            // A full swipe moves past the middle chapter to either end and oscillates.
            // Drag only the missing horizontal edge, within this exact selector's frame.
            var delta: CGFloat = 0
            if frame.minX < visible.minX { delta = visible.minX - frame.minX + 8 }
            else if frame.maxX > visible.maxX { delta = visible.maxX - frame.maxX - 8 }
            guard delta != 0 else { XCTFail("Fully visible chapter is not enabled/hittable. " + app.debugDescription); return }
            delta = min(visible.width * 0.35, max(-visible.width * 0.35, delta))
            let origin = scroller.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: visible.midX - scroller.frame.minX, dy: visible.midY - scroller.frame.minY))
            let end = origin.withOffset(CGVector(dx: visible.midX + delta - scroller.frame.minX, dy: visible.midY - scroller.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Chapter must fit inside its horizontal selector before tapping. " + app.debugDescription)
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
