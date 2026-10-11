import XCTest

/// Authored, not executed here. Requires the central DEBUG fixture route and Apple runner.
final class ProfileSelfMedalsFlowTests: XCTestCase {
    private var app:XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure=false;app=XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app);app.terminate();app=nil }
    private func launch(_ scenario:String="content") {
        app.launchArguments=["--uitesting-profile-self-medals","--profile-self-medals-scenario",scenario,"--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.staticTexts["Synthetic medal owner"].waitForExistence(timeout:10))
        let picker=app.buttons["social.profile.tabs"];if picker.exists { picker.tap() }
        let tab=app.buttons["Achievements"];if tab.waitForExistence(timeout:3) { tab.tap() } else { app.staticTexts["Achievements"].tap() }
    }
    private var city:XCUIElement { app.staticTexts["Synthetic city medal"] }
    func testOwnMedalsLoadAndOpenExistingWall() {
        launch();XCTAssertTrue(city.waitForExistence(timeout:5));app.buttons["profile.selfMedals.openWall"].tap()
        XCTAssertTrue(app.buttons["profile.badge.medal.0"].waitForExistence(timeout:5))
    }
    func testFailureHasRetryAndNoFalseEmptyState() {
        launch("failure");XCTAssertTrue(app.staticTexts["profile.selfMedals.issue"].waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["profile.selfMedals.empty"].exists)
        app.buttons["profile.selfMedals.retry"].tap();XCTAssertTrue(city.waitForExistence(timeout:5))
    }
    func testPartialHasRetryAndNoFalseEmptyState() {
        launch("partial");XCTAssertTrue(app.buttons["profile.selfMedals.retry"].waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["profile.selfMedals.empty"].exists)
        app.buttons["profile.selfMedals.retry"].tap();XCTAssertTrue(city.waitForExistence(timeout:5))
    }
    func testSuccessfulEmptyRefreshReplacesOldMedals() {
        launch("emptyRefresh");XCTAssertTrue(city.waitForExistence(timeout:5));app.buttons["profile.selfMedals.refresh"].tap()
        XCTAssertTrue(app.staticTexts["profile.selfMedals.empty"].waitForExistence(timeout:5));XCTAssertFalse(city.exists)
    }
    func testOtherMemberHasNoPrivateMedalRead() {
        launch("other");XCTAssertFalse(app.buttons["profile.selfMedals.openWall"].exists);XCTAssertEqual(app.staticTexts["profile.selfMedalsFixture.reads"].label,"Medal reads: 0")
    }
    func testGuestHasNoPrivateMedalRead() {
        launch("guest");XCTAssertFalse(app.buttons["profile.selfMedals.openWall"].exists);XCTAssertEqual(app.staticTexts["profile.selfMedalsFixture.reads"].label,"Medal reads: 0")
    }
}
