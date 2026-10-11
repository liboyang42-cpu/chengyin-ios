import XCTest

final class ProfileCasePortfolioFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "success") {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-profile-edit-fixture", scenario]
        app.launch(); XCTAssertTrue(app.staticTexts["profile.edit.fixture.notice"].waitForExistence(timeout: 10))
    }
    private func openCase() -> XCUIElement {
        let button = app.buttons["profile.fieldEdit.open.caseIntroduction"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        let field = app.textFields["profile.edit.caseIntroduction"]
        if field.waitForExistence(timeout: 2) { return field }
        let multiline = app.textViews["profile.edit.caseIntroduction"]
        XCTAssertTrue(multiline.waitForExistence(timeout: 3)); return multiline
    }
    func testCancelReopenThenStageDescriptionWithoutLosingOtherFields() {
        launch(); let field = openCase(), original = field.value as? String
        field.tap(); field.typeText(" Cancelled"); app.buttons["profile.fieldEdit.cancel"].tap()
        let reopened = openCase(); XCTAssertEqual(reopened.value as? String, original)
        reopened.tap(); reopened.typeText(" Staged"); app.buttons["profile.fieldEdit.apply"].tap()
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.caseIntroduction"].label.contains("Staged"))
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.name"].label.contains("Trail Friend"))
    }
    func testCaseOnlyEditAppearsInWholeProfileReviewAndVerifiedReadback() {
        launch(); let field = openCase(); field.tap(); field.typeText(" Updated")
        app.buttons["profile.fieldEdit.apply"].tap(); app.swipeUp()
        let review = app.buttons["profile.edit.review"]; XCTAssertTrue(review.isEnabled); review.tap()
        XCTAssertTrue(app.staticTexts["City photo stories Updated"].waitForExistence(timeout: 5))
        app.buttons["profile.edit.confirm"].tap()
        let status = app.staticTexts["profile.edit.status"]; XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Your profile was saved and verified.")
    }
    func testEmptyPortfolioShowsExplicitEmptyStateWithoutUploadAction() {
        launch(); _ = openCase()
        XCTAssertTrue(app.otherElements["profile.case.imagesEmpty"].exists || app.staticTexts["No portfolio images"].exists)
        XCTAssertTrue(app.staticTexts["Existing images can be previewed. Adding, removing and uploading images are not available yet."].exists)
    }
    func testExistingImageGalleryClosesBackToRetainedCaseScratch() {
        launch("portfolioImages"); let field = openCase(); field.tap(); field.typeText(" Retained")
        app.swipeUp()
        let image = app.buttons["media.gallery.open.0"]; XCTAssertTrue(image.waitForExistence(timeout: 5)); image.tap()
        XCTAssertTrue(app.staticTexts["media.gallery.position"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["media.gallery.position"].label, "1 / 2")
        app.buttons["media.gallery.next"].tap(); XCTAssertEqual(app.staticTexts["media.gallery.position"].label, "2 / 2")
        app.buttons["media.gallery.close"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue((field.value as? String)?.contains("Retained") == true)
        app.buttons["profile.fieldEdit.cancel"].tap()
        let reopened = openCase(); XCTAssertEqual(reopened.value as? String, "City photo stories")
    }
}
