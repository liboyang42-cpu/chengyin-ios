import XCTest

final class PrivateHomeFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "privateHome", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + flags
        app.launch(); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]
        // Form rows below the visible region are lazy: reveal before querying existence.
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    private func captureRetryEvidence(_ app: XCUIApplication, stage: String) {
        // Explicitly synthetic fixture only; includes phase and the existing payload-free
        // request/receipt recorder so an undispatched tap is distinct from replay failure.
        attachFixtureScreenshot(self, app: app, name: "Private home exact retry " + stage)
        let evidence = XCTAttachment(string: stage + "\n" + app.debugDescription)
        evidence.name = "Private home exact retry phase and recorder " + stage
        evidence.lifetime = .keepAlways
        add(evidence)
    }
    private func review(_ app: XCUIApplication) {
        for (id, value) in [("privateHome.label", "Synthetic home"), ("privateHome.latitude", "12.345"), ("privateHome.longitude", "45.678")] {
            let field = app.textFields[id]; XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue(revealFixtureElement(field, in: app))
            field.tap(); field.typeText(value)
        }
        tap("privateHome.reviewSet", app)
    }
    func testDisabledFeatureNeverRequestsLocationOrShowsMutationControls() {
        let app = launch(["--private-home-disabled"])
        XCTAssertTrue(app.staticTexts["Not enabled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["privateHome.reviewSet"].exists); XCTAssertFalse(app.buttons["privateHome.confirm"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testCancelReviewDoesNotSaveAndRemovesSensitiveDraft() {
        let app = launch(); review(app); tap("privateHome.cancel", app)
        XCTAssertTrue(app.staticTexts["No private home saved"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["privateHome.confirm"].exists)
        XCTAssertEqual(app.textFields["privateHome.label"].value as? String, "Private label")
    }
    func testLostResponseLocksNewChangesAndExactRetrySettles() {
        let app = launch(["--private-home-lost", "--private-home-map-recorder"]); review(app); tap("privateHome.confirm", app)
        XCTAssertTrue(app.buttons["privateHome.retry"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["privateHome.reviewSet"].exists)
        tap("privateHome.refresh", app)
        XCTAssertTrue(app.buttons["privateHome.retry"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["privateHome.reviewSet"].exists)
        captureRetryEvidence(app, stage: "before tap")
        tap("privateHome.retry", app)
        captureRetryEvidence(app, stage: "after tap")
        XCTAssertTrue(app.staticTexts["Private home saved"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["privateHome.retry"].exists, app.debugDescription)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testDeleteRequiresReviewAndClearsHome() {
        let app = launch(); review(app); tap("privateHome.confirm", app)
        tap("privateHome.reviewDelete", app); tap("privateHome.cancel", app)
        XCTAssertTrue(app.staticTexts["Private home saved"].exists)
        tap("privateHome.reviewDelete", app); tap("privateHome.confirm", app)
        XCTAssertTrue(app.staticTexts["No private home saved"].waitForExistence(timeout: 5))
    }
}
