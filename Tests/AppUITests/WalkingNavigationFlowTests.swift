import XCTest

/// Authored offline UI acceptance. Real routing/GPS/permissions are deliberately absent.
final class WalkingNavigationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", chinese: Bool = false, maximumType: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US",
            "--uitesting-module", "searchMap", "--uitesting-search-map-entry", "walking", "--uitesting-walking-scenario", scenario]
        if maximumType { app.launchArguments += ["--uitesting-max-text", "--uitesting-dark", "--uitesting-reduce-motion"] }
        app.launch()
        if maximumType { assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility5") }
        let open = app.buttons["walking.open"]; XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertTrue(revealFixtureElement(open, in: app, maximumSwipes: 20)); open.tap()
        XCTAssertTrue(app.buttons["walking.start"].waitForExistence(timeout: 5))
    }
    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        for _ in 0..<16 {
            if button.exists && button.isHittable { break }
            let summary = app.scrollViews["walking.summary"]
            if summary.exists { summary.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(button.exists); XCTAssertTrue(button.isHittable); button.tap()
    }
    func testFactoryRouteShowsStepsDistanceETAAndCancelResume() {
        launch(); tap("walking.start")
        XCTAssertTrue(app.staticTexts["Synthetic authorized stop"].waitForExistence(timeout: 5))
        tap("walking.steps.open")
        revealStep(app.descendants(matching: .any)["walking.step.0"])
        revealStep(app.staticTexts["walking.provider"])
        XCTAssertEqual(app.staticTexts["walking.provider"].label, "Apple Maps")
        tap("walking.steps.close")
        tap("walking.steps.open")
        XCTAssertTrue(app.buttons["walking.steps.close"].waitForExistence(timeout: 5))
        tap("walking.steps.close")
        tap("walking.cancel")
        XCTAssertFalse(app.staticTexts["Synthetic authorized stop"].exists)
        tap("walking.start")
        XCTAssertTrue(app.staticTexts["Synthetic authorized stop"].waitForExistence(timeout: 5))
    }
    private func revealStep(_ element: XCUIElement) {
        let list = app.descendants(matching: .any)["walking.steps.list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 40 { break }
            // Begin inside the foreground sheet, never in the presenting map/summary.
            list.swipeUp()
        }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
        XCTAssertLessThan(element.frame.maxY, app.frame.maxY - 40)
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
    func testRoutingCanBeCancelledWithoutLateRouteAndReopened() {
        launch("routing"); tap("walking.start")
        XCTAssertTrue(app.staticTexts["Planning a walking route…"].waitForExistence(timeout: 5))
        tap("walking.cancel")
        XCTAssertTrue(app.staticTexts["Navigation cancelled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["walking.steps.open"].exists)
        tap("walking.start")
        XCTAssertTrue(app.buttons["walking.steps.open"].waitForExistence(timeout: 5))
    }
    func testExpiredScopeDismissesStepsAndClearsDestination() {
        launch("expiredScope"); tap("walking.start"); tap("walking.steps.open")
        XCTAssertTrue(app.buttons["walking.steps.close"].waitForExistence(timeout: 5))
        // Scope changes only after the actual steps sheet has been observed.
        tap("walking.fixture.expireScope")
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["walking.steps.close"])
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 12), .completed)
        XCTAssertTrue(app.staticTexts["Your session changed. Reopen navigation from the current account."].exists)
        XCTAssertFalse(app.staticTexts["Synthetic authorized stop"].exists)
        XCTAssertFalse(app.buttons["walking.start"].exists)
    }
    func testNearDestinationKeepsVerificationBoundary() {
        launch("nearDestination"); tap("walking.start")
        XCTAssertTrue(app.staticTexts["Near the destination; verification is still required"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["walking.arrivalBoundary"].exists)
        XCTAssertFalse(app.buttons["walking.openVerification"].exists)
        attachFixtureScreenshot(self, app: app, name: "Walking near destination with verification boundary")
    }
    func testMaximumBilingualSummaryAndNativeStepsCanCloseAndReopen() {
        for chinese in [false, true] {
            launch("longText", chinese: chinese, maximumType: true); tap("walking.start")
            XCTAssertTrue(app.staticTexts["walking.destination"].waitForExistence(timeout: 5))
            attachFixtureScreenshot(self, app: app, name: "Walking summary maximum text \(chinese ? "Chinese" : "English")")
            tap("walking.steps.open")
            XCTAssertTrue(app.buttons["walking.steps.close"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.descendants(matching: .any)["walking.steps.list"].firstMatch.value as? String,
                           "dynamicTypeSize=accessibility5", app.debugDescription)
            attachFixtureScreenshot(self, app: app, name: "Walking large native steps \(chinese ? "Chinese" : "English")")
            tap("walking.steps.close"); tap("walking.steps.open"); tap("walking.steps.close")
            app.terminate()
        }
    }

}
