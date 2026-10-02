import XCTest
final class JourneyRoleViewFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ scenario: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-module", "journeyContent", "--uitesting-journey-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]; app.launch(); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]; for _ in 0..<6 { if button.exists && button.isHittable { break }; app.swipeUp() }; XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
    }
    func testAssignedASeesOnlyOwnViewAndCanCloseReopen() {
        let app = launch("roleA")
        XCTAssertTrue(app.staticTexts["roleView.body.A"].waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["roleView.body.B"].exists)
        tap("roleView.close", app); XCTAssertFalse(app.staticTexts["roleView.body.A"].exists)
        tap("roleView.reopen", app); XCTAssertTrue(app.staticTexts["roleView.body.A"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["journey.fixture.mainTask"].exists)
    }
    func testAssignedBHasNoRolePickerOrAContent() {
        let app = launch("roleB")
        XCTAssertTrue(app.staticTexts["roleView.body.B"].waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["roleView.body.A"].exists); XCTAssertEqual(app.pickers.count, 0)
    }
    func testSoloShowsBothServerProvidedViews() {
        let app = launch("roleSolo")
        XCTAssertTrue(app.staticTexts["roleView.body.A"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["roleView.body.B"].exists)
    }
    func testMissingAssignmentHidesAllPrivateContentAndLeavesMainTask() {
        let app = launch("roleMissing", language: "zh-Hans")
        XCTAssertTrue(app.otherElements["roleView.missing"].waitForExistence(timeout: 5) || app.staticTexts["roleView.missing"].exists)
        XCTAssertFalse(app.staticTexts["roleView.body.A"].exists); XCTAssertFalse(app.staticTexts["roleView.body.B"].exists); XCTAssertTrue(app.buttons["journey.fixture.mainTask"].exists)
    }
    func testMixedRoleResponseIsWithheldInsteadOfFilteredOrGuessed() {
        let app = launch("roleMismatch")
        XCTAssertTrue(app.staticTexts["roleView.unavailable"].waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["Must not render A"].exists); XCTAssertFalse(app.staticTexts["Must not render B"].exists)
    }
}
