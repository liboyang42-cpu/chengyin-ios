import XCTest

/// Complete UI1 review journey, independently grouped; no assertions or helper semantics removed.
final class ProjectEditReviewReadinessFlowTests: XCTestCase {
    private var launchedApp: XCUIApplication?
    override func tearDown() {
        if let app = launchedApp { attachFailureScreenshot(self, app: app); app.terminate() }
        launchedApp = nil
        super.tearDown()
    }
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit"] + flags
        launchedApp = app; app.launch(); return app
    }
    private func find(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(element.isHittable)
    }
    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }
    // UNMEASURED full-method estimate: 190s = retained 150s floor + 40s bounded reveal allowance.
    func testLocalEditReviewAndCancelledConfirmation() {
        let app = launch(); let name = app.textFields["projectEdit.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); replace(name, with: "Reviewed fixture name")
        app.buttons["projectEdit.review"].tap()
        XCTAssertTrue(revealFixtureElement(app.staticTexts["Reviewed fixture name"], in: app, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Reviewed fixture name"].waitForExistence(timeout: 3))
        let cancel = app.buttons["projectEdit.cancelReview"]; find(cancel, in: app); cancel.tap()
        XCTAssertTrue(app.buttons["projectEdit.review"].exists)
        XCTAssertFalse(app.staticTexts["Simulation completed. No project was published."].exists)
    }
}
