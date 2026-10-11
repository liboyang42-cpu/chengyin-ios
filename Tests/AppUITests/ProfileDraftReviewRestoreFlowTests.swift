import XCTest

final class ProfileDraftReviewRestoreFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-profile-edit-fixture", "caseRemoval"]
        app.launch(); XCTAssertTrue(app.staticTexts["profile.edit.fixture.notice"].waitForExistence(timeout: 10))
    }
    private func changeName(_ suffix: String = " Local") {
        let entry = app.buttons["profile.fieldEdit.open.name"]; if !entry.isHittable { app.swipeDown() }; entry.tap()
        let field = app.textFields["profile.edit.name"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(suffix)
        app.buttons["profile.fieldEdit.apply"].tap()
    }
    private func review() {
        let button = app.buttons["profile.edit.review"]; if !button.isHittable { app.swipeUp() }; button.tap()
        XCTAssertTrue(app.buttons["profile.reviewRestore.open"].waitForExistence(timeout: 5))
    }
    func testCompareShowsBeforeAndAfterForChangedFieldOnly() {
        launch(); changeName(); review(); app.buttons["profile.reviewRestore.compare"].tap()
        XCTAssertTrue(app.staticTexts["Before"].exists); XCTAssertTrue(app.staticTexts["After saving"].exists)
        XCTAssertTrue(app.staticTexts["Trail Friend"].exists); XCTAssertTrue(app.staticTexts["Trail Friend Local"].exists)
    }
    func testDiscardConfirmationCancelPreservesReviewAndDraft() {
        launch(); changeName(); review(); app.buttons["profile.reviewRestore.open"].tap()
        app.buttons["profile.reviewRestore.cancel"].tap(); XCTAssertTrue(app.buttons["profile.edit.confirm"].exists)
        app.buttons["profile.edit.cancel"].tap(); XCTAssertTrue(app.buttons["profile.edit.review"].isEnabled)
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.name"].label.contains("Local"))
    }
    func testDiscardStaysOnPageAndDoesNotReportServerSave() {
        launch(); changeName(); review(); app.buttons["profile.reviewRestore.open"].tap(); app.buttons["profile.reviewRestore.confirm"].tap()
        let status = app.staticTexts["profile.edit.status"]; XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Local changes were discarded. Nothing was saved.")
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled); XCTAssertTrue(app.buttons["profile.fieldEdit.open.name"].exists)
    }
    func testDiscardRestoresImagesAsWellAsText() {
        launch(); changeName(); app.buttons["profile.caseRemoval.open"].tap()
        app.buttons["profile.caseRemoval.remove"].tap(); app.buttons["profile.caseRemoval.apply"].tap(); review()
        app.buttons["profile.reviewRestore.open"].tap(); app.buttons["profile.reviewRestore.confirm"].tap()
        let images = app.buttons["profile.caseRemoval.open"]; if !images.isHittable { app.swipeDown() }; images.tap()
        XCTAssertTrue(app.buttons["profile.caseRemoval.remove"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["profile.caseRemoval.restore"].exists)
    }
    func testDiscardThenEditAndSaveIsStillAvailable() {
        launch(); changeName(); review(); app.buttons["profile.reviewRestore.open"].tap(); app.buttons["profile.reviewRestore.confirm"].tap()
        changeName(" Saved"); review(); app.buttons["profile.edit.confirm"].tap()
        let status = app.staticTexts["profile.edit.status"]; XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Your profile was saved and verified.")
    }
}
