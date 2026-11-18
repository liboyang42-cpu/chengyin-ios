import XCTest
final class JourneyRoleViewFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ scenario: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "journeyContent", "--uitesting-journey-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]; app.launch(); return app
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
    func testOnlyOneActiveMemberGetsSoloFullViewWithRoleHeadings() {
        // The server degrades a team with one active member to SOLO and sends every role's view.
        let app = launch("roleSoloSingle")
        for role in ["A", "B", "C"] {
            XCTAssertTrue(app.staticTexts["roleView.body." + role].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.staticTexts["roleView.heading." + role].exists, app.debugDescription)
        }
        XCTAssertEqual(app.staticTexts["roleView.heading.A"].label, "Synthetic guide")
        XCTAssertEqual(app.staticTexts["roleView.heading.C"].label, "Synthetic keeper")
        XCTAssertFalse(app.staticTexts["roleView.teammatesOther"].exists)
        XCTAssertTrue(app.buttons["journey.fixture.mainTask"].exists)
    }
    func testAssignedThirdRoleSeesOwnLabelAndOtherRoleLabelsOnly() {
        let app = launch("roleC", language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["roleView.body.C"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["roleView.body.A"].exists); XCTAssertFalse(app.staticTexts["roleView.body.B"].exists)
        XCTAssertEqual(app.staticTexts["roleView.assignment"].label, "你的角色：Synthetic keeper")
        XCTAssertTrue(app.staticTexts["roleView.teammatesOther"].exists)
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
