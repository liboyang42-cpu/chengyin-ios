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
        // iOS 26 exposes wrapper buttons as well: scope to the presented sheet and
        // select the hittable leaf carrying this exact identifier, never first global match.
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let leaves = sheet.buttons.matching(identifier: "profile.edit.confirm")
            .matching(NSPredicate(format: "hittable == true AND enabled == true"))
        XCTAssertTrue(leaves.firstMatch.waitForExistence(timeout: 5)); leaves.firstMatch.tap()
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
