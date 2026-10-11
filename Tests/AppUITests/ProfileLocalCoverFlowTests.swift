import XCTest

/// Uses synthetic image injection, then the production preview/confirm/cancel UI.
/// Never opens or approves the system photo picker.
final class ProfileLocalCoverFlowTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app=XCUIApplication(); app.launchArguments += ["--uitesting","--uitesting-profile-local-cover"]; app.launch(); return app
    }
    private func tap(_ key: String,_ app: XCUIApplication) {
        let b=app.buttons[key]; XCTAssertTrue(b.waitForExistence(timeout:3)); if !b.isHittable { app.swipeUp() }; b.tap()
    }
    func testCancelPreviewLeavesDefaultWithoutAnyWrites() {
        let app=launch(); tap("profile.localCoverFixture.prepare",app)
        XCTAssertTrue(app.images["profile.localCover.preview"].waitForExistence(timeout:3))
        tap("profile.localCover.close",app)
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.writes"].label,"Writes: 0")
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.state"].label,"Default")
    }
    func testConfirmCoverThenRereadFromStore() {
        let app=launch(); tap("profile.localCoverFixture.prepare",app); tap("profile.localCover.confirm",app)
        XCTAssertTrue(app.images["profile.localCover.preview"].waitForExistence(timeout:3))
        tap("profile.localCoverFixture.reload",app)
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.writes"].label,"Writes: 1")
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.state"].label,"Saved")
    }
    func testRestoreDefaultCanBeCancelledThenConfirmed() {
        let app=launch(); tap("profile.localCoverFixture.prepare",app); tap("profile.localCover.confirm",app)
        tap("profile.localCover.edit",app); tap("profile.localCover.restore",app); tap("profile.localCover.cancelReview",app)
        tap("profile.localCover.close",app)
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.writes"].label,"Writes: 1")
        tap("profile.localCover.edit",app); tap("profile.localCover.restore",app); tap("profile.localCover.confirm",app)
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.state"].label,"Default")
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.writes"].label,"Writes: 2")
    }
    func testSwitchAccountDoesNotDisplayFormerCover() {
        let app=launch(); tap("profile.localCoverFixture.prepare",app); tap("profile.localCover.confirm",app)
        tap("profile.localCoverFixture.switch",app)
        XCTAssertTrue(app.otherElements["profile.localCover.default"].waitForExistence(timeout:3))
        XCTAssertFalse(app.images["profile.localCover.preview"].exists)
    }
    func testSignedOutAccountCannotEditOrDisplayCover() {
        let app=launch(); tap("profile.localCoverFixture.prepare",app); tap("profile.localCover.confirm",app)
        tap("profile.localCoverFixture.logout",app)
        XCTAssertFalse(app.buttons["profile.localCover.edit"].exists); XCTAssertFalse(app.images["profile.localCover.preview"].exists)
    }
}
