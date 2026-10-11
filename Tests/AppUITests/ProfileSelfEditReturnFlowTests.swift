import XCTest

/// Authored only: requires the central DEBUG fixture registration and an Apple runner.
final class ProfileSelfEditReturnFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure=false;app=XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app);app.terminate();app=nil }
    private func launch(_ scenario:String="own") {
        app.launchArguments=["--uitesting-profile-self-edit-return","--profile-self-edit-scenario",scenario,"--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.staticTexts["Synthetic profile"].waitForExistence(timeout:10))
        let picker=app.buttons["social.profile.tabs"]
        if picker.exists { picker.tap() }
        let about=app.buttons["About"]
        if about.waitForExistence(timeout:3) { about.tap() }
        else { app.staticTexts["About"].tap() }
    }
    private func open() {
        let button=app.buttons["profile.selfEdit.open"];XCTAssertTrue(button.waitForExistence(timeout:5));button.tap()
        XCTAssertTrue(app.buttons["profile.fieldEdit.open.introduction"].waitForExistence(timeout:5))
    }
    private func stage() {
        app.buttons["profile.fieldEdit.open.introduction"].tap()
        let field=app.textViews["profile.edit.introduction"];XCTAssertTrue(field.waitForExistence(timeout:5));field.tap();field.typeText(" updated")
        app.buttons["profile.fieldEdit.apply"].tap()
    }
    func testOwnPublicAboutCanOpenAndCancelExistingEditor() {
        launch();open();app.buttons["profile.exitDiscard.back"].tap()
        XCTAssertTrue(app.buttons["profile.selfEdit.open"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["Original public introduction"].exists)
        XCTAssertTrue(app.staticTexts["profile.selfEditFixture.counts"].label.contains("Writes: 0"))
    }
    func testDiscardReturnsOriginalPublicDataWithoutSave() {
        launch();open();stage();app.buttons["profile.exitDiscard.back"].tap()
        let discard=app.buttons["profile.exitDiscard.confirm"];XCTAssertTrue(discard.waitForExistence(timeout:5));discard.tap()
        XCTAssertTrue(app.staticTexts["Original public introduction"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["profile.selfEditFixture.counts"].label.contains("Writes: 0"))
    }
    func testSavedEditorReturnsFreshPublicIntroduction() {
        launch();open();stage();app.swipeUp();app.buttons["profile.edit.review"].tap()
        let confirm=app.buttons.matching(identifier:"profile.edit.confirm").firstMatch;XCTAssertTrue(confirm.waitForExistence(timeout:5));confirm.tap()
        XCTAssertTrue(app.staticTexts["profile.edit.status"].waitForExistence(timeout:5));app.buttons["profile.exitDiscard.back"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","introduction updated")).firstMatch.waitForExistence(timeout:5))
    }
    func testReturnReadFailureExposesReadRetry() {
        launch();app.buttons["profile.selfEditFixture.failRead"].tap();open();app.buttons["profile.exitDiscard.back"].tap()
        XCTAssertTrue(app.otherElements["social.issue"].waitForExistence(timeout:5));app.buttons["Retry"].tap()
        XCTAssertTrue(app.staticTexts["Original public introduction"].waitForExistence(timeout:5))
    }
    func testOtherMemberHasNoSelfEditor() { launch("other");XCTAssertFalse(app.buttons["profile.selfEdit.open"].exists) }
    func testGuestHasNoSelfEditor() { launch("guest");XCTAssertFalse(app.buttons["profile.selfEdit.open"].exists) }
}
