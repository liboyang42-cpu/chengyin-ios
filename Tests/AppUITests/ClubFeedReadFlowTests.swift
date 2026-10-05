import XCTest

/// Synthetic source-authored flows only; Apple execution is a separate gate.
final class ClubFeedReadFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil
    }
    private func launch(_ scenario: String = "content", chineseLargeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-club-governance", "--club-feed-scenario", scenario]
        if chineseLargeText { app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); tap("club.gov.openFeed", app: app); return app
    }
    private func tap(_ id: String, app: XCUIApplication) {
        if ["media.gallery.close", "club.feed.fixture.switch", "club.feed.fixture.replace"].contains(id) {
            tapChrome(id, app: app); return
        }
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        XCTAssertTrue(button.isHittable); button.tap()
    }
    // Fixed fixture header and the presented gallery's navigation bar are not
    // scrollable feed content. Never generate feed refresh gestures to reach them.
    private func tapChrome(_ id: String, app: XCUIApplication) {
        let gallery = id == "media.gallery.close"
        guard gallery || ["club.feed.fixture.switch", "club.feed.fixture.replace"].contains(id) else {
            XCTFail("Unknown fixture chrome target"); return
        }
        let query = gallery ? app.navigationBars.buttons.matching(identifier: id) : app.buttons.matching(identifier: id)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard query.count == 1 else { return false }
            let button = query.element(boundBy: 0), frame = button.frame
            guard button.exists, button.isEnabled, button.isHittable, !frame.isEmpty, app.frame.contains(frame) else { return false }
            let bars = app.navigationBars.allElementsBoundByIndex.filter { $0.exists && !$0.frame.isEmpty }
            if gallery { return bars.contains { $0.frame.contains(frame) } }
            let counter = app.staticTexts["club.feed.fixture.imageReads"]
            guard counter.exists, let firstBar = bars.first else { return false }
            return frame.minY >= counter.frame.maxY && frame.maxY <= firstBar.frame.minY
        }, object: app)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            XCTFail("Expected exact unique enabled visible fixture chrome: " + app.debugDescription); return
        }
        query.element(boundBy: 0).tap()
    }
    private func absent(_ id: String, app: XCUIApplication) {
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.descendants(matching: .any)[id].firstMatch)
        waitForExpectations(timeout: 5)
    }
    func testSourceClubUsesActualDetailAndCanReopenAfterBackWithoutFeedPages() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Fixture feed author"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["club.feed.time.191"].exists)
        XCTAssertFalse(app.buttons["club.gov.previous"].exists); XCTAssertFalse(app.buttons["club.gov.next"].exists)
        XCTAssertFalse(app.staticTexts["PRIVATE-CONTACT-MUST-NOT-APPEAR"].exists)
        for _ in 0..<2 {
            tap("club.feed.source.191", app: app)
            let name = app.staticTexts["club.detail.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5)); XCTAssertEqual(name.label, "Actual source club 81")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons["club.feed.source.191"].waitForExistence(timeout: 5))
        }
    }
    func testChineseLargeTextGalleryUsesThreeImagesAndReturnsToSameSource() {
        let app = launch(chineseLargeText: true)
        tap("media.gallery.open.2", app: app)
        XCTAssertTrue(app.staticTexts["media.gallery.position"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["media.gallery.position"].label, "3 / 3")
        tap("media.gallery.close", app: app)
        tap("club.feed.source.191", app: app)
        XCTAssertTrue(app.staticTexts["club.detail.name"].waitForExistence(timeout: 5))
        attachFixtureScreenshot(self, app: app, name: "Club feed Chinese large-text source detail")
    }
    func testMissingSourceClubIsNoninteractiveAndDefaultMediaStaysDisabled() {
        var app = launch("invalidClub")
        XCTAssertTrue(app.staticTexts["Fixture source club"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.feed.source.191"].exists)
        app.terminate(); app = launch("disabled")
        XCTAssertTrue(app.staticTexts["Fixture feed author"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["club.feed.fixture.imageReads"].label, "0")
        tap("club.feed.source.191", app: app)
        XCTAssertTrue(app.staticTexts["club.detail.name"].waitForExistence(timeout: 5))
    }
    func testNoClubsEmptyPostsAndUnknownCountRemainDifferentStates() {
        for (scenario, expected) in [("noClubs", "club.feed.emptyNoClubs"), ("empty", "club.feed.emptyPosts"), ("unknownCount", "club.gov.error")] {
            let app = launch(scenario)
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.buttons["club.feed.source.191"].exists)
            if scenario == "unknownCount" { XCTAssertFalse(app.staticTexts["club.feed.emptyNoClubs"].exists) }
            app.terminate()
        }
    }
    func testReadFailureRetriesAndReplacementRevisionUsesNewSourceClub() {
        let app = launch("failure")
        XCTAssertTrue(app.staticTexts["club.gov.error"].waitForExistence(timeout: 5))
        tap("club.gov.refresh", app: app)
        XCTAssertTrue(app.staticTexts["Fixture feed author"].waitForExistence(timeout: 5))
        tap("club.feed.fixture.replace", app: app)
        XCTAssertTrue(app.staticTexts["Replacement feed author"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Fixture feed author"].exists)
        tap("club.feed.source.191", app: app)
        XCTAssertTrue(app.staticTexts["club.detail.name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["club.detail.name"].label, "Actual source club 82")
    }
    func testAccountChangeClosesSelectedClubAndClearsPriorFeed() {
        let app = launch()
        tap("club.feed.source.191", app: app)
        XCTAssertTrue(app.staticTexts["club.detail.name"].waitForExistence(timeout: 5))
        tap("club.feed.fixture.switch", app: app)
        absent("club.detail.name", app: app)
        XCTAssertTrue(app.staticTexts["club.gov.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.feed.source.191"].exists)
        XCTAssertFalse(app.staticTexts["Fixture feed author"].exists)
    }
}
