import XCTest

final class NativeVerificationFlowTests: XCTestCase {
    private func launch(_ scenario: String = "success") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--native-verification-fixture", scenario, "-AppleLanguages", "(en)"]
        app.launch(); return app
    }
    private func review(_ app: XCUIApplication) {
        let field = app.secureTextFields["verification.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("cq1.synthetic.example.signature")
        let button = app.buttons["verification.review"]
        for _ in 0..<4 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.isHittable); button.tap()
        XCTAssertTrue(app.buttons["verification.confirm"].waitForExistence(timeout: 5))
    }
    func testSyntheticReviewAndAcknowledgedResult() {
        let app = launch(); review(app); app.buttons["verification.confirm"].tap()
        XCTAssertTrue(app.otherElements["verification.result"].waitForExistence(timeout: 5))
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
