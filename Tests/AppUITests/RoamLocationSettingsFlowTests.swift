import XCTest

final class RoamLocationSettingsFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", "content",
            "--uitesting-roam-location-settings-scenario", scenario, "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        runningApp = app; app.launch()
        let open = app.buttons["roam.locationSettings.open"]
        XCTAssertTrue(revealFixtureElement(open, in: app)); open.tap(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func assertStatus(_ status: String) {
        let app = app(status)
        XCTAssertTrue(element("roam.locationSettings.authorization." + status, app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertTrue(app.buttons["roam.locationSettings.openSettings"].exists)
    }
    func testNotDeterminedIsNotPresentedAsDenied() { assertStatus("notDetermined") }
    func testDeniedIsVisibleWithoutPermissionPrompt() { assertStatus("denied") }
    func testRestrictedIsDistinctFromDenied() { assertStatus("restricted") }
    func testWhenInUseDoesNotClaimAlways() {
        let app = app("whenInUse")
        XCTAssertTrue(element("roam.locationSettings.always.notGranted", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("roam.locationSettings.always.granted", app).exists)
    }
    func testAlwaysStatusHasCapabilityBoundaryText() {
        let app = app("always")
        XCTAssertTrue(element("roam.locationSettings.always.granted", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["System permission does not enable live roaming, background recording, or arrival reminders in this app."].exists)
    }
    func testSystemLocationServicesOffIsSeparateFromAuthorization() {
        let app = app("servicesDisabled")
        XCTAssertTrue(element("roam.locationSettings.services.disabled", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("roam.locationSettings.authorization.whenInUse", app).exists)
    }
    func testExplicitRefreshShowsNewReadAndBackKeepsOwnedWalletEntry() {
        let app = app("refreshChanges")
        XCTAssertTrue(element("roam.locationSettings.authorization.denied", app).waitForExistence(timeout: 5))
        app.buttons["roam.locationSettings.refresh"].tap()
        XCTAssertTrue(element("roam.locationSettings.authorization.whenInUse", app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(revealFixtureElement(app.buttons["roam.ownedCoupons.open"], in: app))
        XCTAssertTrue(revealFixtureElement(app.buttons["roam.locationSettings.open"], in: app))
    }
    func testFailedOpenCanRetryWithoutLeavingAppOrPrompting() {
        let app = app("denied")
        XCTAssertTrue(element("roam.locationSettings.authorization.denied", app).waitForExistence(timeout: 5))
        app.buttons["roam.locationSettings.openSettings"].tap()
        XCTAssertTrue(element("roam.locationSettings.openFailed", app).waitForExistence(timeout: 5))
        app.buttons["roam.locationSettings.openSettings"].tap()
        XCTAssertTrue(element("roam.locationSettings.openFailed", app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testReadFailureRetryDoesNotGuessDenied() {
        let app = app("readFailure")
        XCTAssertTrue(element("roam.locationSettings.readFailed", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("roam.locationSettings.authorization.denied", app).exists)
        app.buttons["roam.locationSettings.retry"].tap()
        XCTAssertTrue(element("roam.locationSettings.authorization.whenInUse", app).waitForExistence(timeout: 5))
    }
    func testActiveReturnRefreshesWithoutOpeningDeviceSettings() {
        let app = app("refreshChanges")
        XCTAssertTrue(element("roam.locationSettings.authorization.denied", app).waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(element("roam.locationSettings.authorization.whenInUse", app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }
}
