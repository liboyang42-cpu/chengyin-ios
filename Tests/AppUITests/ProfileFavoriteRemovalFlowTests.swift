import XCTest
final class ProfileFavoriteRemovalFlowTests: XCTestCase {
    private func launch(_ scenario:String="success")->XCUIApplication {
        let app=XCUIApplication();app.launchArguments += ["--uitesting","--uitesting-profile-favorite-removal","--profile-favorite-removal-scenario",scenario];app.launch();return app
    }
    private func tap(_ key:String,_ app:XCUIApplication) { let b=app.buttons[key];XCTAssertTrue(b.waitForExistence(timeout:3));if !b.isHittable {app.swipeUp()};b.tap() }
    func testCancelDoesNotWriteOrRemoveCard() {
        let app=launch();tap("profile.favoriteRemoval.open.101",app)
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.confirm"].waitForExistence(timeout:3));tap("profile.favoriteRemoval.close",app)
        XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label,"Writes: 0");XCTAssertTrue(app.buttons["profile.favoriteRemoval.open.101"].exists)
    }
    func testConfirmedReadbackRefreshesCollection() {
        let app=launch();tap("profile.favoriteRemoval.open.101",app);tap("profile.favoriteRemoval.confirm",app);tap("profile.favoriteRemoval.done",app)
        XCTAssertTrue(app.staticTexts["profile.favoriteFixture.refreshed"].waitForExistence(timeout:3));XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label,"Writes: 1")
    }
    func testUnknownCannotResubmitAndCanCheckAfterReopen() {
        let app=launch("unknown");tap("profile.favoriteRemoval.open.101",app);tap("profile.favoriteRemoval.confirm",app)
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.check"].waitForExistence(timeout:3));XCTAssertFalse(app.buttons["profile.favoriteRemoval.confirm"].exists)
        tap("profile.favoriteRemoval.close",app);tap("profile.favoriteFixture.resolve",app);tap("profile.favoriteRemoval.open.101",app);tap("profile.favoriteRemoval.check",app);tap("profile.favoriteRemoval.done",app)
        XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label,"Writes: 1")
    }
    func testReadFailureRetryOnlyPreparesReview() {
        let app=launch("readFailure");tap("profile.favoriteRemoval.open.101",app);tap("profile.favoriteRemoval.retry",app)
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.confirm"].waitForExistence(timeout:3));tap("profile.favoriteRemoval.close",app)
        XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label,"Writes: 0")
    }
    func testDisabledGrantDoesNotShowFakeAction() {
        let app=launch("disabled");XCTAssertTrue(app.staticTexts["profile.favoriteFixture.writes"].waitForExistence(timeout:3));XCTAssertFalse(app.buttons["profile.favoriteRemoval.open.101"].exists)
    }
    func testVerifiedRemovalCloseAlsoRefreshesCollection() {
        let app = launch(); tap("profile.favoriteRemoval.open.101", app)
        tap("profile.favoriteRemoval.confirm", app)
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.done"].waitForExistence(timeout: 3))
        tap("profile.favoriteRemoval.close", app)
        XCTAssertTrue(app.staticTexts["profile.favoriteFixture.refreshed"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label, "Writes: 1")
    }
    func testVerifiedRemovalSwipeAlsoRefreshesCollection() {
        let app = launch(); tap("profile.favoriteRemoval.open.101", app)
        tap("profile.favoriteRemoval.confirm", app)
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.done"].waitForExistence(timeout: 3))
        let bar = app.navigationBars["Remove saved post"]
        XCTAssertTrue(bar.waitForExistence(timeout: 3)); bar.swipeDown()
        XCTAssertTrue(app.staticTexts["profile.favoriteFixture.refreshed"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label, "Writes: 1")
    }
    func testAppliedUnknownMissingRowCanRecoverAndKeepResultSheetUntilDone() {
        let app = launch("ackUnreadable"); tap("profile.favoriteRemoval.open.101", app)
        tap("profile.favoriteRemoval.confirm", app)
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.check"].waitForExistence(timeout: 3))
        tap("profile.favoriteRemoval.close", app)
        tap("profile.favoriteFixture.refreshList", app)
        XCTAssertFalse(app.buttons["profile.favoriteRemoval.open.101"].exists)
        tap("profile.favoriteFixture.resolve", app)
        tap("profile.favoriteRecovery.open.101", app)
        XCTAssertFalse(app.buttons["profile.favoriteRemoval.confirm"].exists)
        tap("profile.favoriteRemoval.check", app)
        // The journal row disappeared, but the presentation still owns its result.
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.done"].waitForExistence(timeout: 3))
        tap("profile.favoriteRemoval.done", app)
        XCTAssertTrue(app.staticTexts["profile.favoriteFixture.refreshed"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["profile.favoriteRecovery.open.101"].exists)
        XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label, "Writes: 1")
    }

}
