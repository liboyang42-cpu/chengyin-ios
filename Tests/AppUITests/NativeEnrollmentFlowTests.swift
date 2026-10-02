import XCTest

final class NativeEnrollmentFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ scenario: String = "ready", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-module", "nativeEnrollment", "--uitesting-enrollment-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    private func tap(_ id: String, app: XCUIApplication) {
        let button = app.buttons[id]; XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription); button.tap()
    }
    private func prepare(_ app: XCUIApplication) { tap("nativeEnrollment.create", app: app); tap("nativeEnrollment.confirm", app: app) }
    private func enroll(_ app: XCUIApplication) { prepare(app); tap("nativeEnrollment.enroll", app: app); tap("nativeEnrollment.confirm", app: app) }
    func testDefaultOffCannotCreatePersistentAccess() {
        let app = launch("disabled")
        XCTAssertTrue(app.staticTexts["Device enrollment is not enabled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nativeEnrollment.create"].exists); XCTAssertFalse(app.buttons["nativeEnrollment.enroll"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testCancellingPurposeNeverPreparesAnEnrollment() {
        let app = launch(); tap("nativeEnrollment.create", app: app)
        XCTAssertTrue(app.buttons["nativeEnrollment.confirm"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["nativeEnrollment.create"].exists); XCTAssertFalse(app.buttons["nativeEnrollment.enroll"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testPreparationRequiresSeparateAccountEnrollmentReview() {
        let app = launch(); prepare(app)
        XCTAssertTrue(app.buttons["nativeEnrollment.enroll"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["nativeEnrollment.revoke"].exists)
        tap("nativeEnrollment.enroll", app: app); tap("nativeEnrollment.confirm", app: app)
        XCTAssertTrue(app.staticTexts["Server confirms this key is active"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nativeEnrollment.revoke"].exists); XCTAssertEqual(app.alerts.count, 0)
    }
    func testLostEnrollmentExposesExactRetry() {
        let app = launch("lost-enroll"); enroll(app)
        XCTAssertTrue(app.buttons["nativeEnrollment.retryEnroll"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nativeEnrollment.create"].exists)
        tap("nativeEnrollment.retryEnroll", app: app)
        XCTAssertTrue(app.staticTexts["Server confirms this key is active"].waitForExistence(timeout: 5)); XCTAssertEqual(app.alerts.count, 0)
    }
    func testRevocationIsExplicitAndConfirmedByStatusReadback() {
        let app = launch("lost-revoke"); enroll(app)
        tap("nativeEnrollment.revoke", app: app); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["nativeEnrollment.revoke"].exists)
        tap("nativeEnrollment.revoke", app: app); tap("nativeEnrollment.confirm", app: app)
        XCTAssertTrue(app.buttons["nativeEnrollment.retryRevoke"].waitForExistence(timeout: 5))
        tap("nativeEnrollment.refresh", app: app)
        XCTAssertTrue(app.staticTexts["Server confirms this key is revoked"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nativeEnrollment.retryRevoke"].exists); XCTAssertEqual(app.alerts.count, 0)
    }
    func testChineseEnrollmentPurposeIsLocalized() {
        let app = launch(language: "zh-Hans"); tap("nativeEnrollment.create", app: app)
        XCTAssertTrue(app.navigationBars["审核设备验证"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["创建密钥并准备证明"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
}
