import XCTest

/// Only the added camera/preview journeys. The original eight route-map tests are unchanged.
final class PlayRouteMapCameraFallbackFlowTests: XCTestCase {
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


    func testPreviewChoicesExcludeLockedHiddenAndClearAfterReadChanges() {
        launch(); tap("playRouteCamera.choose")
        XCTAssertFalse(app.buttons["playRouteCamera.choice.702"].exists)
        XCTAssertFalse(app.buttons["playRouteCamera.choice.703"].exists)
        tap("playRouteCamera.choice.700"); expectPreview("Synthetic completed stop")
        tap("playRoute.fixture.controls"); tap("playRoute.fixture.read")
        XCTAssertFalse(previewName.exists)
        tap("playRouteCamera.current"); expectPreview("Synthetic refreshed stop")
        tap("playRouteCamera.overview"); XCTAssertFalse(previewName.exists)
    }
    func testUnsupportedExtentLeavesExplicitManualListFallback() {
        launch("routeMapFocusPolar"); tap("playRouteCamera.overview")
        let issue = app.staticTexts["playRouteCamera.issue"]
        XCTAssertTrue(issue.exists); XCTAssertTrue(issue.label.contains("cannot be safely fitted"))
        tap("playRouteCamera.current"); expectPreview("Synthetic polar stop")
        XCTAssertTrue(issue.exists)
        tap("playRouteCamera.openTask")
        XCTAssertTrue(app.staticTexts["Synthetic polar stop"].waitForExistence(timeout: 5))
    }
    func testChineseMaximumTextPreviewControlsRetainFullMeaningAndReturnToOverview() {
        launch(chinese: true, maximum: true)
        tap("playRouteCamera.current"); expectPreview("Synthetic current stop")
        choose(700); expectPreview("Synthetic completed stop")
        let open = app.buttons["playRouteCamera.openTask"]
        XCTAssertTrue(revealFixtureElement(open, in: app, maximumSwipes: 20))
        XCTAssertEqual(open.label, "打开此任务")
        tap("playRouteCamera.overview"); XCTAssertFalse(previewName.exists)
        XCTAssertTrue(app.navigationBars["路线地图"].exists)
        attachFixtureScreenshot(self, app: app, name: "Chinese maximum text camera overview and preview")
    }
}
