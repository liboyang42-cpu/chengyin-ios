import XCTest

final class ProfileContactQRRemovalFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-profile-edit-fixture", "contactQR"]
        app.launch(); XCTAssertTrue(app.staticTexts["profile.edit.fixture.notice"].waitForExistence(timeout: 10))
    }
    private func openQR() {
        let entry = app.buttons["profile.contactQR.open"]
        if !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.buttons["profile.contactQR.apply"].waitForExistence(timeout: 5))
    }
    func testLocalRemovalCancelLeavesExistingQRCode() {
        launch(); openQR(); app.buttons["profile.contactQR.remove"].tap()
        XCTAssertTrue(app.buttons["profile.contactQR.restore"].exists)
        app.buttons["profile.contactQR.cancel"].tap(); openQR()
        XCTAssertTrue(app.buttons["profile.contactQR.remove"].exists)
        XCTAssertFalse(app.buttons["profile.contactQR.restore"].exists)
    }
    func testStageReopenAndRestoreRemovalBeforeSaving() {
        launch(); openQR(); app.buttons["profile.contactQR.remove"].tap(); app.buttons["profile.contactQR.apply"].tap()
        XCTAssertTrue(app.buttons["profile.contactQR.open"].label.contains("Pending removal"))
        openQR(); app.buttons["profile.contactQR.restore"].tap(); app.buttons["profile.contactQR.apply"].tap()
        XCTAssertTrue(app.buttons["profile.contactQR.open"].label.contains("Added"))
        XCTAssertFalse(app.buttons["profile.edit.review"].isEnabled)
    }
    func testRemovalIsReviewedAndSavedThroughExistingProfileFlow() {
        launch(); openQR(); app.buttons["profile.contactQR.remove"].tap(); app.buttons["profile.contactQR.apply"].tap()
        app.swipeUp(); app.buttons["profile.edit.review"].tap()
        XCTAssertTrue(app.staticTexts["The contact QR code will be removed."].waitForExistence(timeout: 5))
        app.buttons["profile.edit.confirm"].tap()
        let status = app.staticTexts["profile.edit.status"]; XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Your profile was saved and verified.")
        openQR(); XCTAssertFalse(app.buttons["profile.contactQR.remove"].exists)
        XCTAssertTrue(app.staticTexts["Not added"].exists || app.otherElements["profile.contactQR.empty"].exists)
    }
    func testViewerEntryClosesWithoutChangingRemovalIntent() {
        launch(); openQR()
        let image = app.buttons["media.gallery.open.0"]; XCTAssertTrue(image.waitForExistence(timeout: 5)); image.tap()
        XCTAssertTrue(app.staticTexts["media.gallery.position"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["media.gallery.position"].label, "1 / 1")
        app.buttons["media.gallery.close"].tap(); XCTAssertTrue(app.buttons["profile.contactQR.remove"].exists)
        app.buttons["profile.contactQR.cancel"].tap()
        let review = app.buttons["profile.edit.review"]
        if !review.isHittable { app.swipeUp() }
        XCTAssertTrue(review.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(review.isEnabled)
    }
    func testSwipeDismissDoesNotStageLocalRemoval() {
        launch(); openQR(); app.buttons["profile.contactQR.remove"].tap()
        app.navigationBars.element(boundBy: app.navigationBars.count - 1).swipeDown()
        XCTAssertTrue(app.buttons["profile.contactQR.open"].waitForExistence(timeout: 5))
        openQR(); XCTAssertTrue(app.buttons["profile.contactQR.remove"].exists)
    }
}
