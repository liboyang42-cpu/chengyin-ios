import XCTest

final class NativeVerificationFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ scenario: String = "success") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--native-verification-fixture", scenario, "-AppleLanguages", "(en)"]
        runningApp = app; app.launch(); return app
    }
    private func review(_ app: XCUIApplication) {
        let field = app.secureTextFields["verification.code"]
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "verification.screen").firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(field, in: app), app.debugDescription); field.tap(); field.typeText("cq1.synthetic.example.signature")
        let button = app.buttons["verification.review"]
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        XCTAssertTrue(button.isHittable); button.tap()
        XCTAssertTrue(app.buttons["verification.confirm"].waitForExistence(timeout: 5))
    }
    func testSyntheticReviewAndAcknowledgedResult() {
        let app = launch(); review(app); app.buttons["verification.confirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "verification.result").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["verification.fixtureCount"].label, "1")
    }
    func testCancelReviewMakesNoMutation() {
        let app = launch(); review(app); app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.secureTextFields["verification.code"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["verification.fixtureCount"].label, "0")
    }
    func testUnknownResultOffersReadbackAndKeepsCaptureLockedAfterReturn() {
        let app = launch("unknown"); review(app); app.buttons["verification.confirm"].tap()
        let readback = app.buttons["verification.readback"]
        XCTAssertTrue(readback.waitForExistence(timeout: 5)); readback.tap()
        XCTAssertTrue(app.staticTexts["verification.fixtureRecords"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["verification.readback"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["verification.code"].exists)
        XCTAssertEqual(app.staticTexts["verification.fixtureCount"].label, "1")
    }
}
