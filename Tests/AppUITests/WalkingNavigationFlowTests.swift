import XCTest

/// Authored offline UI acceptance. Real routing/GPS/permissions are deliberately absent.
final class WalkingNavigationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US",
            "--uitesting-module", "searchMap", "--uitesting-search-map-entry", "walking", "--uitesting-walking-scenario", scenario]
        app.launch()
        let open = app.buttons["walking.open"]; XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        XCTAssertTrue(app.buttons["walking.start"].waitForExistence(timeout: 5))
    }
    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        for _ in 0..<10 { if button.exists && button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.exists); XCTAssertTrue(button.isHittable); button.tap()
    }
    func testFactoryRouteShowsStepsDistanceETAAndCancelResume() {
        launch(); tap("walking.start")
        XCTAssertTrue(app.staticTexts["Synthetic authorized stop"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Apple Maps"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["walking.step.0"].exists)
        tap("walking.cancel")
        XCTAssertFalse(app.staticTexts["Synthetic authorized stop"].exists)
        tap("walking.start")
        XCTAssertTrue(app.staticTexts["Synthetic authorized stop"].waitForExistence(timeout: 5))
    }
    func testPermissionDeniedNeverShowsRouteSteps() {
        launch("permissionDenied"); tap("walking.start")
        XCTAssertTrue(app.staticTexts["Location permission is denied. You can change it in system settings."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["walking.step.0"].exists)
    }
    func testNoRouteIsUnavailableWithoutStraightLineFallback() {
        launch("noRoute"); tap("walking.start")
        XCTAssertTrue(app.staticTexts["No walking route is available."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["walking.step.0"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.route.fallback"].exists)
    }
    func testLockedTargetDoesNotRevealDestinationOrRoute() {
        launch("locked"); tap("walking.start")
        XCTAssertTrue(app.staticTexts["This destination is no longer available. Refresh the current task."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic authorized stop"].exists)
    }
    func testChinesePauseAndAccountChangeClearRoute() {
        launch(chinese: true); tap("walking.start")
        XCTAssertTrue(app.staticTexts["Synthetic authorized stop"].waitForExistence(timeout: 5))
        tap("walking.pause"); XCTAssertTrue(app.staticTexts["导航已暂停；继续时重新获取目的地和路线"].exists)
        for _ in 0..<10 { if app.buttons["searchMap.fixture.account"].isHittable { break }; app.swipeDown() }
        app.buttons["searchMap.fixture.account"].tap()
        XCTAssertFalse(app.staticTexts["Synthetic authorized stop"].exists)
        XCTAssertFalse(app.buttons["walking.open"].exists)
    }
}
