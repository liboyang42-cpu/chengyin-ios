import XCTest

/// Authored only; central fixture registration and an Apple runner are required.
final class ProfileSelfGrowthFlowTests:XCTestCase {
    private var app:XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure=false;app=XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app);app.terminate();app=nil }
    private func launch(_ scenario:String="content") {
        app.launchArguments=["--uitesting-profile-self-growth","--profile-self-growth-scenario",scenario,"--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.staticTexts["Synthetic growth owner"].waitForExistence(timeout:10))
        let picker=app.buttons["social.profile.tabs"];if picker.exists {picker.tap()}
        let tab=app.buttons["Achievements"];if tab.waitForExistence(timeout:3) {tab.tap()}else{app.staticTexts["Achievements"].tap()}
    }
    func testOwnSummaryOpensExistingGrowthCenter() {
        launch();XCTAssertTrue(app.staticTexts["700"].waitForExistence(timeout:5));app.buttons["profile.selfGrowth.openCenter"].tap()
        XCTAssertTrue(app.buttons["growth.openLeaderboard"].waitForExistence(timeout:5))
    }
    func testReadFailureRetriesWithoutEmptyOrSavedClaim() {
        launch("failure");let retry=app.buttons["growth.retry"];XCTAssertTrue(retry.waitForExistence(timeout:5));retry.tap();XCTAssertTrue(app.staticTexts["700"].waitForExistence(timeout:5))
    }
    func testPartialCenterShowsIssueAlongsideKnownCheckins() {
        launch("partialCenter");XCTAssertTrue(app.buttons["growth.retry"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["12"].exists);XCTAssertFalse(app.staticTexts["700"].exists)
    }
    func testRefreshCanRereadKnownZeroValues() {
        launch("zero");let refresh=app.buttons["profile.selfGrowth.refresh"];XCTAssertTrue(refresh.waitForExistence(timeout:5));refresh.tap()
        let refreshed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@","2"),object:app.staticTexts["profile.selfGrowthFixture.reads"])
        XCTAssertEqual(XCTWaiter.wait(for:[refreshed],timeout:5),.completed)
    }
    func testOtherMemberCannotReadOwnGrowth() { launch("other");XCTAssertFalse(app.buttons["profile.selfGrowth.openCenter"].exists);XCTAssertEqual(app.staticTexts["profile.selfGrowthFixture.reads"].label,"Growth reads: 0") }
    func testGuestCannotReadOwnGrowth() { launch("guest");XCTAssertFalse(app.buttons["profile.selfGrowth.openCenter"].exists);XCTAssertEqual(app.staticTexts["profile.selfGrowthFixture.reads"].label,"Growth reads: 0") }
}
