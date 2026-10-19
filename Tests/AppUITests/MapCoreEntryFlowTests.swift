import XCTest

/// Offline authored UI tests for the map entry hub fixture. No session, location or network.
final class MapCoreEntryFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(chinese: Bool = false, accessible: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-map-core-entry"]
        if accessible { app.launchArguments += ["--uitesting-large-text", "--uitesting-dark", "--uitesting-reduce-motion"] }
        app.launch()
    }
    private func reveal(_ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription)
    }

    func testExistingEntryOpensAndPendingEntriesStayDisabled() {
        launch()
        let city = app.buttons["mapCore.entry.cityOrienteering"]
        XCTAssertTrue(city.waitForExistence(timeout: 5)); XCTAssertTrue(city.isEnabled)
        city.tap()
        XCTAssertEqual(app.staticTexts["mapCore.fixture.opened"].label, "cityOrienteering")
        for pending in ["merchantSideQuests", "personalFog", "sharedLocation", "cityOperation"] {
            let button = app.buttons["mapCore.entry.\(pending)"]
            reveal(button); XCTAssertFalse(button.isEnabled, pending)
        }
        XCTAssertEqual(app.staticTexts["mapCore.fixture.opened"].label, "cityOrienteering")
    }
    func testLegendNamesEveryStateAndMarksCandidatePalette() {
        launch()
        for state in ["standard", "interactive", "selected", "active", "completed", "locked", "unavailable", "inReview"] {
            reveal(app.descendants(matching: .any)["mapCore.legend.\(state)"])
        }
        reveal(app.staticTexts["mapCore.legend.candidate"])
    }
    func testSharingIsOffAndStartStaysDisabledAfterAllConfirmations() {
        launch()
        reveal(app.descendants(matching: .any)["mapCore.share.status"])
        XCTAssertTrue(app.staticTexts["Off"].exists)
        let explain = app.buttons["mapCore.share.explain"]; reveal(explain); explain.tap()
        for item in ["audience", "precision", "duration", "foregroundOnly", "stopAnytime", "alreadySeenCannotBeRecalled"] {
            let toggle = app.switches["mapCore.share.disclosure.\(item)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), item)
            reveal(toggle)
            // The switch frame includes its multiline label; touch the trailing native control.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
            XCTAssertEqual(XCTWaiter.wait(for: [on], timeout: 5), .completed, item)
        }
        let start = app.buttons["mapCore.share.start"]; reveal(start)
        XCTAssertFalse(start.isEnabled)
        XCTAssertTrue(app.staticTexts["mapCore.share.unavailable"].exists)
        app.buttons["mapCore.share.close"].tap()
        XCTAssertTrue(app.staticTexts["Off"].waitForExistence(timeout: 5))
    }
    func testChineseLargeTextDarkKeepsEntriesReadable() {
        launch(chinese: true, accessible: true)
        XCTAssertTrue(app.buttons["mapCore.entry.cityOrienteering"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["城市定向主线"].exists)
        reveal(app.buttons["mapCore.entry.cityOperation"])
        XCTAssertFalse(app.buttons["mapCore.entry.cityOperation"].isEnabled)
    }
}
