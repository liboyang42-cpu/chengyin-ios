import XCTest

final class ProfilePreferenceRemovalFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-profile-edit-fixture", "preferenceRemoval"]
        app.launch(); XCTAssertTrue(app.staticTexts["profile.edit.fixture.notice"].waitForExistence(timeout: 10))
    }
    private func openPreferences() {
        let entry = app.buttons["profile.preferenceRemoval.open"]
        if !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.buttons["profile.preferenceRemoval.apply"].waitForExistence(timeout: 5))
    }
    func testUnavailableCatalogueItemCanBeRemovedLocallyAndCancelled() {
        launch(); openPreferences(); XCTAssertTrue(app.staticTexts["Retired category"].exists)
        app.buttons["profile.preferenceRemoval.remove.7007"].tap(); XCTAssertTrue(app.buttons["profile.preferenceRemoval.restore.7007"].exists)
        app.buttons["profile.preferenceRemoval.cancel"].tap(); openPreferences()
        XCTAssertTrue(app.buttons["profile.preferenceRemoval.remove.7007"].exists)
    }
    func testRestoreAndUndoAllLeavePageUnchanged() {
        launch(); openPreferences(); app.buttons["profile.preferenceRemoval.remove.7007"].tap()
        app.buttons["profile.preferenceRemoval.restore.7007"].tap(); app.buttons["profile.preferenceRemoval.clear"].tap()
        app.buttons["profile.preferenceRemoval.undoAll"].tap(); app.buttons["profile.preferenceRemoval.apply"].tap()
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
    }
    func testRemoveReviewSaveAndReopenShowsOnlyVerifiedSelection() {
        launch(); openPreferences(); app.buttons["profile.preferenceRemoval.remove.7007"].tap(); app.buttons["profile.preferenceRemoval.apply"].tap()
        app.swipeUp(); app.buttons["profile.edit.review"].tap()
        XCTAssertTrue(app.otherElements["profile.preferenceRemoval.review"].waitForExistence(timeout: 5) || app.staticTexts["Selected preference IDs"].exists)
        app.buttons["profile.edit.confirm"].tap(); let status = app.staticTexts["profile.edit.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10)); XCTAssertEqual(status.label, "Your profile was saved and verified.")
        openPreferences(); XCTAssertTrue(app.buttons["profile.preferenceRemoval.remove.4"].exists)
        XCTAssertFalse(app.buttons["profile.preferenceRemoval.remove.7007"].exists)
    }
    func testClearAllStagesEmptySelectionWithoutCatalogueRequest() {
        launch(); openPreferences(); app.buttons["profile.preferenceRemoval.clear"].tap(); app.buttons["profile.preferenceRemoval.apply"].tap()
        openPreferences(); XCTAssertTrue(app.staticTexts["profile.preferenceRemoval.empty"].exists)
    }
    func testSwipeDismissDiscardsLocalRemoval() {
        launch(); openPreferences(); app.buttons["profile.preferenceRemoval.remove.7007"].tap()
        app.navigationBars.element(boundBy: app.navigationBars.count - 1).swipeDown()
        XCTAssertTrue(app.buttons["profile.preferenceRemoval.open"].waitForExistence(timeout: 5))
        openPreferences(); XCTAssertTrue(app.buttons["profile.preferenceRemoval.remove.7007"].exists)
    }
}
