import XCTest

/// Synthetic scenarios only. Runtime, VoiceOver and provider behavior require Apple execution.
final class PlayRouteMapFlowTests: XCTestCase {
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
    func testCurrentCompletedAndOldTaskEntrancesRemainReachable() {
        launch(); openMap()
        XCTAssertTrue(app.descendants(matching: .any)["playRoute.map"].exists)
        tap("playRoute.openCurrent")
        XCTAssertTrue(app.navigationBars["Journey task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic current story"].exists)
        backFromTask(); tap("playRoute.toggleMap"); tap("playRoute.stop.700")
        XCTAssertTrue(app.navigationBars["Journey task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic completed stop"].exists)
        backFromTask(); tap("playRoute.back")
        tap("playx.node.701")
        XCTAssertTrue(app.navigationBars["Journey task"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        attachFixtureScreenshot(self, app: app, name: "Orientation map returns to existing task")
    }
    func testMissingCoordinatesKeepCompleteEquivalentList() {
        launch("routeMapMissing"); openMap()
        XCTAssertTrue(app.staticTexts["playRoute.noCoordinates"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["playRoute.map"].exists)
        tap("playRoute.stop.701"); XCTAssertTrue(app.staticTexts["Synthetic current story"].waitForExistence(timeout: 5))
        backFromTask(); tap("playRoute.stop.700")
        XCTAssertTrue(app.staticTexts["Synthetic completed stop"].waitForExistence(timeout: 5))
    }
    func testLockedAndHiddenStopsCannotLeakOrOpenFromMap() {
        launch(); openMap(); tap("playRoute.toggleMap")
        let locked = app.descendants(matching: .any).matching(identifier: "playRoute.stop.702").firstMatch
        XCTAssertTrue(revealFixtureElement(locked, in: app), app.debugDescription)
        XCTAssertFalse(app.buttons["playRoute.stop.702"].exists)
        XCTAssertFalse(app.buttons["playRoute.pin.702"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["playRoute.stop.703"].exists)
        for secret in ["Locked spoiler name", "Locked spoiler story", "Locked spoiler address", "Hidden spoiler name", "Hidden spoiler story"] {
            XCTAssertFalse(app.staticTexts[secret].exists, secret)
        }
        XCTAssertFalse(app.buttons["playx.answer.review"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attachFixtureScreenshot(self, app: app, name: "Map locked placeholder with no future content")
    }
    func testSameNodeIDReadRefreshClearsPushedSelectionAndReopensCurrentRead() {
        launch(); openMap(); tap("playRoute.openCurrent")
        XCTAssertTrue(app.navigationBars["Journey task"].waitForExistence(timeout: 5))
        fixtureAction("playRoute.fixture.read")
        XCTAssertTrue(app.navigationBars["Route map"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Synthetic refreshed stop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Journey task"].exists)
        tap("playRoute.openCurrent"); XCTAssertTrue(app.staticTexts["Synthetic refreshed stop"].waitForExistence(timeout: 5))
    }





}
