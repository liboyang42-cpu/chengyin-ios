import XCTest

final class NativePlatformFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ scenario: String = "ready", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "nativePlatform", "--uitesting-native-platform-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    private func tap(_ id: String, app: XCUIApplication) {
        let button = app.buttons[id]; XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        XCTAssertTrue(button.isEnabled, app.debugDescription); button.tap()
    }
    private func openFixture(_ destination: String, app: XCUIApplication) {
        let id = "nativePlatform.fixture." + destination
        let link = app.buttons[id]
        XCTAssertTrue(link.waitForExistence(timeout: 5), app.debugDescription)
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true AND value == %@", "ready"), object: link)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
        tap(id, app: app)
        let kind = destination == "reminder" ? "timeWindow" : "steps"
        XCTAssertTrue(app.scrollViews["playkit.screen." + kind].waitForExistence(timeout: 5),
                      "The single fixture navigation tap did not reach its screen. " + app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["nativePlatform." + destination + ".host"].firstMatch.waitForExistence(timeout: 5),
                      "The destination did not render its native host. " + app.debugDescription)
    }
    func testDefaultOffNormalStepsHostNeverPrompts() {
        let app = launch("disabled"); openFixture("steps", app: app)
        XCTAssertTrue(app.staticTexts["nativePlatform.steps.disabled"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["nativePlatform.steps.read"].exists); XCTAssertEqual(app.alerts.count, 0)
    }
    func testCancelStepPurposeDoesNotReadOrSubmit() {
        let app = launch(); openFixture("steps", app: app); tap("nativePlatform.steps.read", app: app)
        XCTAssertTrue(app.buttons["nativePlatform.steps.consent"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["nativePlatform.steps.count"].exists); XCTAssertFalse(app.buttons["nativePlatform.steps.send"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testStepsRequireTwoExplicitStagesAndDisplayAuditOnlyResult() {
        let app = launch(); openFixture("steps", app: app); tap("nativePlatform.steps.read", app: app); tap("nativePlatform.steps.consent", app: app)
        XCTAssertTrue(app.staticTexts["nativePlatform.steps.count"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["nativePlatform.steps.count"].label, "1234")
        tap("nativePlatform.steps.send", app: app)
        XCTAssertTrue(app.staticTexts["Audit sample recorded by service"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Passed"].exists); XCTAssertEqual(app.alerts.count, 0)
    }
    func testReminderOptInReadbackAndCancellationAreLocal() {
        let app = launch(); openFixture("reminder", app: app)
        XCTAssertFalse(app.staticTexts["nativePlatform.reminder.scheduled"].exists)
        tap("nativePlatform.reminder.enable", app: app); tap("nativePlatform.reminder.consent", app: app)
        XCTAssertTrue(app.staticTexts["nativePlatform.reminder.scheduled"].waitForExistence(timeout: 5), app.debugDescription)
        tap("nativePlatform.reminder.cancel", app: app)
        XCTAssertTrue(app.buttons["nativePlatform.reminder.enable"].exists); XCTAssertFalse(app.staticTexts["nativePlatform.reminder.scheduled"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testDeniedNotificationDoesNotShowScheduled() {
        let app = launch("denied"); openFixture("reminder", app: app)
        XCTAssertTrue(app.staticTexts["nativePlatform.reminder.issue"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.staticTexts["nativePlatform.reminder.issue"].label, "Permission is off. You can change it in iPhone Settings.")
        XCTAssertFalse(app.staticTexts["nativePlatform.reminder.scheduled"].exists); XCTAssertEqual(app.alerts.count, 0)
    }
    func testChineseNativeReminderUsesTranslatedPurpose() {
        let app = launch(language: "zh-Hans"); openFixture("reminder", app: app); tap("nativePlatform.reminder.enable", app: app)
        XCTAssertTrue(app.navigationBars["允许本机提醒？"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["允许并设置此提醒"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
}
