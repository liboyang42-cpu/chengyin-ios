import XCTest

/// Only the added camera/preview journeys. The original eight route-map tests are unchanged.
final class PlayRouteMapCameraFlowTests: XCTestCase {
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
        tap("playRoute.open"); tap("playRouteCamera.controls")
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(revealFixtureElement(button, in: app, maximumSwipes: 20), app.debugDescription)
        XCTAssertTrue(button.isEnabled, app.debugDescription); button.tap()
    }
    private var previewName: XCUIElement { app.staticTexts["playRouteCamera.preview.name"] }
    private func choose(_ id: Int) { tap("playRouteCamera.choose"); tap("playRouteCamera.choice.\(id)") }
    private func expectPreview(_ name: String) {
        XCTAssertTrue(previewName.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(previewName.label, name)
    }
    func testOverviewCurrentAndOtherStopPreviewFormCompleteInspectionJourney() {
        launch(); tap("playRouteCamera.current"); expectPreview("Synthetic current stop")
        choose(700); expectPreview("Synthetic completed stop")
        XCTAssertTrue(app.buttons["playRoute.openCurrent"].exists, "Preview cannot replace the current task")
        tap("playRouteCamera.overview"); XCTAssertFalse(previewName.exists)
        tap("playRouteCamera.current"); expectPreview("Synthetic current stop")
        choose(700); tap("playRouteCamera.openTask")
        XCTAssertTrue(app.navigationBars["Journey task"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic completed stop"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Route map"].waitForExistence(timeout: 5))
        attachFixtureScreenshot(self, app: app, name: "Route overview current and inspected stop remain separate")
    }
    func testCurrentWithoutCoordinatesKeepsMapUnmovedAndTaskReachable() {
        launch("routeMapFocusMissingCurrent"); tap("playRouteCamera.current")
        expectPreview("Synthetic current stop")
        let issue = app.staticTexts["playRouteCamera.issue"]
        XCTAssertTrue(issue.exists); XCTAssertTrue(issue.label.contains("camera has not moved"))
        tap("playRouteCamera.openTask")
        XCTAssertTrue(app.staticTexts["Synthetic current story"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        choose(700); expectPreview("Synthetic completed stop")
        XCTAssertFalse(app.staticTexts["playRouteCamera.issue"].exists)
    }



}
