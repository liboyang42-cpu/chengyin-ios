import XCTest

final class ProfileEditFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app); app.terminate(); app = nil }
    private func launch(_ scenario: String) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-profile-edit-fixture", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["profile.edit.fixture.notice"].waitForExistence(timeout: 10))
    }
    private func editAndReview() {
        let field = app.textFields["profile.edit.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText(" Updated")
        app.swipeUp()
        let review = app.buttons["profile.edit.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5)); review.tap()
    }
    private func confirm() {
        // SwiftUI sheet is rendered but is not necessarily an XCUIElementTypeSheet.
        // Verify its title and reviewed value, then target its unique actionable control.
        XCTAssertTrue(app.navigationBars["Review profile changes"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Trail Friend Updated"].exists, app.debugDescription)
        let leaves = app.buttons.matching(identifier: "profile.edit.confirm")
        // Hittability is not supported in XCUIElementQuery's server-side predicate subset.
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            leaves.allElementsBoundByIndex.contains { $0.exists && $0.isEnabled && $0.isHittable }
        },object:app)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed,app.debugDescription)
        guard let button=leaves.allElementsBoundByIndex.reversed().first(where:{ $0.exists && $0.isEnabled && $0.isHittable }) else { XCTFail("Missing profile confirmation action");return }
        button.tap()
    }
    func testFailedReloadKeepsDraftAndAllowsReviewedSave() {
        launch("refreshFailure")
        let field = app.textFields["profile.edit.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText(" Updated")
        app.swipeUp()
        app.buttons["profile.edit.reload"].tap()
        let status = app.staticTexts["profile.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("unsaved changes are kept"))
        XCTAssertEqual(field.value as? String, "Trail Friend Updated")
        XCTAssertTrue(app.buttons["profile.edit.review"].isEnabled)
        app.buttons["profile.edit.review"].tap()
        confirm()
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Your profile was saved and verified.")
    }
    func testConfirmedProfileSaveIsReadBack() {
        launch("success"); editAndReview(); confirm()
        let status = app.staticTexts["profile.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Your profile was saved and verified.")
    }
    func testUnknownWriteLocksReviewAndOffersReadOnlyCheck() {
        launch("unknown"); editAndReview(); confirm()
        let status = app.staticTexts["profile.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("not confirmed"))
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
        app.buttons["profile.edit.reload"].tap()
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
    }
    func testIncompleteSnapshotCannotBeEdited() {
        launch("missing")
        XCTAssertTrue(app.staticTexts["profile.edit.status"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["profile.edit.name"].exists)
    }
}
