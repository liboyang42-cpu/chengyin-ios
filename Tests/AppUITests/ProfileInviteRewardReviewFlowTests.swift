import XCTest

/// Authored only; central fixture registration and Apple runtime are required.
final class ProfileInviteRewardReviewFlowTests:XCTestCase {
    private var app:XCUIApplication!
    override func setUpWithError() throws {continueAfterFailure=false;app=XCUIApplication()}
    override func tearDownWithError() throws {attachFailureScreenshot(self,app:app);app.terminate();app=nil}
    private func launch(_ scenario:String="complete") {
        app.launchArguments=["--uitesting-profile-invite-reward-review","--profile-invite-reward-review-scenario",scenario,"--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.otherElements["social.invites"].waitForExistence(timeout:10) || app.collectionViews.firstMatch.waitForExistence(timeout:10))
    }
    func testCompleteGlobalAndMonthlyTotalsAreDifferentScopes() {launch();XCTAssertTrue(app.staticTexts["profile.inviteRewards.cumulative"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["profile.inviteRewards.cumulative"].label,"11");XCTAssertTrue(app.staticTexts["+7.75"].exists)}
    func testPartialLedgerHasNoFakeCumulativeAndReloadRecovers() {launch("partial");let retry=app.buttons["profile.inviteRewards.reload"];XCTAssertTrue(retry.waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["profile.inviteRewards.cumulative"].exists);retry.tap();XCTAssertTrue(app.staticTexts["profile.inviteRewards.cumulative"].waitForExistence(timeout:5))}
    func testUnavailableLedgerReloadRecovers() {launch("unavailable");let retry=app.buttons["profile.inviteRewards.reload"];XCTAssertTrue(retry.waitForExistence(timeout:5));retry.tap();XCTAssertTrue(app.staticTexts["profile.inviteRewards.cumulative"].waitForExistence(timeout:5))}
    func testTrueZeroRemainsDisplayable() {launch("zero");XCTAssertTrue(app.staticTexts["profile.inviteRewards.cumulative"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["profile.inviteRewards.cumulative"].label,"0")}
    func testLoadMoreAddsOtherMonthWithoutInventedReward() {launch();app.swipeUp();let more=app.buttons["social.invites.more"];XCTAssertTrue(more.waitForExistence(timeout:5));more.tap();XCTAssertTrue(app.staticTexts["Synthetic Cy"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["2026-09"].exists)}
    func testGuestCannotLoadRewardReview() {launch("guest");XCTAssertFalse(app.staticTexts["profile.inviteRewards.cumulative"].exists);XCTAssertEqual(app.staticTexts["profile.inviteRewardsFixture.reads"].label,"Invitation reads: 0")}
}
