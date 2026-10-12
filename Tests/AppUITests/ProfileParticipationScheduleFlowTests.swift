import XCTest

/// Synthetic local UI only; production participation read approval stays blocked.
final class ProfileParticipationScheduleFlowTests:XCTestCase {
    private var app:XCUIApplication!
    override func setUpWithError() throws {continueAfterFailure=false;app=XCUIApplication()}
    override func tearDownWithError() throws {attachFailureScreenshot(self,app:app);app.terminate();app=nil}
    private func launch(_ scenario:String="near") {app.launchArguments=["--uitesting-profile-participation-schedule","--profile-participation-schedule-scenario",scenario,"--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"];app.launch();XCTAssertTrue(app.staticTexts["profile.participationScheduleFixture.notice"].waitForExistence(timeout:10))}
    func testNearStartShowsTwoDaysAndRange() {launch();XCTAssertTrue(app.staticTexts["profile.participationSchedule.soon"].exists);XCTAssertEqual(app.staticTexts["profile.participationSchedule.days"].label,"2");XCTAssertEqual(app.staticTexts["profile.participationSchedule.range"].label,"2026.10.13 - 2026.10.13")}
    func testAdvancingToStartRemovesReminderWithoutRead() {launch();app.buttons["profile.participationScheduleFixture.advance"].tap();XCTAssertFalse(app.staticTexts["profile.participationSchedule.days"].exists);XCTAssertTrue(app.staticTexts["profile.participationSchedule.range"].exists)}
    func testChangingDisplayTimezoneKeepsShanghaiDays() {launch();app.buttons["profile.participationScheduleFixture.zone"].tap();XCTAssertEqual(app.staticTexts["profile.participationSchedule.days"].label,"2")}
    func testFarFutureShowsRangeWithoutUrgency() {launch("far");XCTAssertFalse(app.staticTexts["profile.participationSchedule.soon"].exists);XCTAssertTrue(app.staticTexts["profile.participationSchedule.range"].exists)}
    func testSameDayDoesNotClaimOneDayRemaining() {launch("sameDay");XCTAssertFalse(app.staticTexts["profile.participationSchedule.days"].exists);XCTAssertTrue(app.staticTexts["profile.participationSchedule.range"].exists)}
    func testMissingAndReversedSchedulesAreNotInvented() {for scenario in ["missing","reversed"] {launch(scenario);XCTAssertFalse(app.staticTexts["profile.participationSchedule.range"].exists);XCTAssertFalse(app.staticTexts["profile.participationSchedule.days"].exists);app.terminate()}}
}
