import XCTest

final class ProfileCasePictureRemovalFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-profile-edit-fixture", "caseRemoval"]
        app.launch(); XCTAssertTrue(app.staticTexts["profile.edit.fixture.notice"].waitForExistence(timeout: 10))
    }
    private func openImages() {
        let entry = app.buttons["profile.caseRemoval.open"]; if !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.buttons["profile.caseRemoval.apply"].waitForExistence(timeout: 5))
    }
    func testClearAllCancelPreservesExistingImages() {
        launch(); openImages(); app.buttons["profile.caseRemoval.remove"].tap(); XCTAssertTrue(app.buttons["profile.caseRemoval.restore"].exists)
        app.buttons["profile.caseRemoval.cancel"].tap(); openImages(); XCTAssertTrue(app.buttons["profile.caseRemoval.remove"].exists)
    }
    func testStageReopenAndKeepAllRestoresUnchangedDraft() {
        launch(); openImages(); app.buttons["profile.caseRemoval.remove"].tap(); app.buttons["profile.caseRemoval.apply"].tap()
        openImages(); app.buttons["profile.caseRemoval.restore"].tap(); app.buttons["profile.caseRemoval.apply"].tap()
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
    }
    func testDescriptionEditorShowsPendingImageRemovalInsteadOfOriginalGallery() {
        launch(); openImages(); app.buttons["profile.caseRemoval.remove"].tap(); app.buttons["profile.caseRemoval.apply"].tap()
        app.buttons["profile.fieldEdit.open.caseIntroduction"].tap()
        XCTAssertTrue(app.staticTexts["profile.caseRemoval.stagedInDescription"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["media.gallery.open.0"].exists)
    }
    func testReviewSaveAndReopenConfirmsAllImagesRemoved() {
        launch(); openImages(); app.buttons["profile.caseRemoval.remove"].tap(); app.buttons["profile.caseRemoval.apply"].tap()
        app.swipeUp(); app.buttons["profile.edit.review"].tap()
        XCTAssertTrue(app.staticTexts["All existing work images will be removed."].waitForExistence(timeout: 5))
        app.buttons["profile.edit.confirm"].tap(); let status = app.staticTexts["profile.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10)); XCTAssertEqual(status.label, "Your profile was saved and verified.")
        openImages(); XCTAssertTrue(app.staticTexts["profile.caseRemoval.empty"].exists); XCTAssertFalse(app.buttons["profile.caseRemoval.remove"].exists)
    }
    func testSwipeDismissDoesNotStageClearAll() {
        launch(); openImages(); app.buttons["profile.caseRemoval.remove"].tap()
        app.navigationBars.element(boundBy: app.navigationBars.count - 1).swipeDown()
        XCTAssertTrue(app.buttons["profile.caseRemoval.open"].waitForExistence(timeout: 5))
        openImages(); XCTAssertTrue(app.buttons["profile.caseRemoval.remove"].exists)
    }
}
