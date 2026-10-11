import XCTest

final class RoamFinishedHistoryFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func app(_ scenario: String = "liveSession") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", scenario,
                               "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        runningApp = app; app.launch()
        tap(app.buttons["roam.experience.live.open"], app: app); return app
    }
    private func tap(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription)
        XCTAssertTrue(element.isEnabled, app.debugDescription); element.tap()
    }
    func testFinishedWalkOpensItsActualStoredRecordAndHistoryThenReturns() {
        let app = app()
        XCTAssertFalse(app.buttons["roam.finishedHistory.record.open"].exists)
        tapFixtureNativeSwitch(app.switches["roam.live.consent"], in: app)
        tap(app.buttons["roam.live.start"], app: app)
        XCTAssertFalse(app.buttons["roam.finishedHistory.record.open"].exists)
        tap(app.buttons["roam.live.finish"], app: app)
        let confirmation = app.sheets["Finish this walk?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        tapFixtureSheetAction("Finish and check results", in: confirmation, app: app)
        tap(app.buttons["roam.finishedHistory.record.open"], app: app)
        XCTAssertTrue(app.staticTexts["Saved local journey"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample district"].exists) // Read the controller's new archive, not the hub's unrelated fixture.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Settled and saved"].waitForExistence(timeout: 5))
        tap(app.buttons["roam.finishedHistory.history.open"], app: app)
        let rows = app.buttons.matching(identifier: "roam.experience.history.record")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5)); XCTAssertEqual(rows.count, 1)
        rows.firstMatch.tap(); XCTAssertTrue(app.staticTexts["Saved local journey"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testUnknownOrRecoveredActiveSessionHasNoSavedContinuation() {
        let app = app("liveUnknown")
        tapFixtureNativeSwitch(app.switches["roam.live.consent"], in: app)
        tap(app.buttons["roam.live.start"], app: app)
        XCTAssertTrue(app.staticTexts["Status needs checking"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roam.finishedHistory.record.open"].exists)
        tap(app.buttons["roam.live.recover"], app: app)
        XCTAssertTrue(app.staticTexts["Paused; no location collection"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roam.finishedHistory.record.open"].exists)
        XCTAssertFalse(app.buttons["roam.finishedHistory.history.open"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
}
