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
    private func tap(_ id: String, towardTop: Bool = false) {
        let button = app.buttons[id]
        XCTAssertTrue(revealFixtureElement(button, in: app, towardTop: towardTop, maximumSwipes: 20), app.debugDescription)
        XCTAssertTrue(button.isEnabled, app.debugDescription); button.tap()
    }
    private var previewName: XCUIElement { app.staticTexts["playRouteCamera.preview.name"] }
    // Preview and issue are separate List rows now, so they can sit below the visible rows.
    private func expectPreview(_ name: String) {
        XCTAssertTrue(revealFixtureElement(previewName, in: app, maximumSwipes: 20, requiresHittable: false), app.debugDescription)
        XCTAssertEqual(previewName.label, name)
    }
    private func expectIssue(containing text: String) {
        let issue = app.staticTexts["playRouteCamera.issue"]
        XCTAssertTrue(revealFixtureElement(issue, in: app, maximumSwipes: 20, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(issue.label.contains(text))
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
        expectIssue(containing: "cannot be safely fitted")
        tap("playRouteCamera.current", towardTop: true); expectPreview("Synthetic polar stop")
        expectIssue(containing: "cannot be safely fitted")
        tap("playRouteCamera.openTask")
        XCTAssertTrue(app.staticTexts["Synthetic polar stop"].waitForExistence(timeout: 5))
    }
    func testChineseMaximumTextPreviewControlsRetainFullMeaningAndReturnToOverview() {
        launch(chinese: true, maximum: true)
        tap("playRouteCamera.current"); expectPreview("Synthetic current stop")
        tap("playRouteCamera.choose", towardTop: true); tap("playRouteCamera.choice.700"); expectPreview("Synthetic completed stop")
        let open = app.buttons["playRouteCamera.openTask"]
        XCTAssertTrue(revealFixtureElement(open, in: app, maximumSwipes: 20))
        XCTAssertEqual(open.label, "打开此任务")
        tap("playRouteCamera.overview", towardTop: true); XCTAssertFalse(previewName.exists)
        XCTAssertTrue(app.navigationBars["路线地图"].exists)
        attachFixtureScreenshot(self, app: app, name: "Chinese maximum text camera overview and preview")
    }
}
