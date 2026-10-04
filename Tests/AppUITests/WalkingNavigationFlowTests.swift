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
    private func summaryContains(_ control: CGRect, viewport: CGRect) -> Bool {
        !control.isEmpty && !viewport.isEmpty && !viewport.isNull && viewport.contains(control)
    }
    func testSummaryVisibilityRejectsMapOcclusionAndOffscreenFrames() {
        let viewport = CGRect(x: 0, y: 438.7, width: 420, height: 473.3)
        XCTAssertFalse(summaryContains(CGRect(x: 20, y: 367.7, width: 309.3, height: 77.3), viewport: viewport))
        XCTAssertTrue(summaryContains(CGRect(x: 20, y: 460, width: 309.3, height: 77.3), viewport: viewport))
        XCTAssertFalse(summaryContains(CGRect(x: 20, y: 880, width: 309.3, height: 77.3), viewport: viewport))
        XCTAssertFalse(summaryContains(.zero, viewport: viewport))
        XCTAssertFalse(summaryContains(CGRect(x: 20, y: 460, width: 309.3, height: 77.3), viewport: .null))
    }
    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        // Native steps Close and synthetic expiry are fixed sheet chrome, not summary content.
        if identifier == "walking.steps.close" || identifier == "walking.fixture.expireScope" {
            XCTAssertTrue(button.exists); XCTAssertTrue(button.isEnabled)
            XCTAssertTrue(button.isHittable); button.tap(); return
        }
        let summary = app.scrollViews["walking.summary"]
        func fullyVisible() -> Bool {
            guard summary.exists, button.exists, !button.frame.isEmpty else { return false }
            return summaryContains(button.frame, viewport: summary.frame.intersection(app.frame))
        }
        for _ in 0..<16 {
            if fullyVisible() && button.isEnabled && button.isHittable { break }
            guard summary.exists else { break }
            // A clipped button can be hittable while its center lies under the map.
            // Scroll only inside the real summary viewport, in the direction of its row.
            let viewport = summary.frame.intersection(app.frame)
            guard !viewport.isNull, !viewport.isEmpty,
                  viewport.minX.isFinite, viewport.minY.isFinite,
                  viewport.width.isFinite, viewport.height.isFinite else { break }
            let towardTop = button.exists && button.frame.midY < viewport.midY
            let start = CGPoint(x: viewport.midX, y: viewport.minY + viewport.height * (towardTop ? 0.3 : 0.75))
            let end = CGPoint(x: viewport.midX, y: viewport.minY + viewport.height * (towardTop ? 0.75 : 0.3))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x - app.frame.minX, dy: start.y - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x - app.frame.minX, dy: end.y - app.frame.minY)))
        }
        XCTAssertTrue(fullyVisible(), app.debugDescription)
        XCTAssertTrue(button.isEnabled); XCTAssertTrue(button.isHittable); button.tap()
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
