import XCTest

/// Authored only. Requires central DEBUG fixture registration and an Apple runner.
final class ProfileSelfProjectsFlowTests: XCTestCase {
    private var app:XCUIApplication!
    override func setUpWithError() throws {continueAfterFailure=false;app=XCUIApplication()}
    override func tearDownWithError() throws {attachFailureScreenshot(self,app:app);app.terminate();app=nil}
    private func launch(_ scenario:String="content",open:Bool=true) {
        app.launchArguments=["--uitesting-profile-self-projects","--profile-self-projects-scenario",scenario,"--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.staticTexts["Synthetic projects owner"].waitForExistence(timeout:10))
        if open {let picker=app.buttons["social.profile.tabs"];if picker.exists {picker.tap()};let tab=app.buttons["My projects"];if tab.waitForExistence(timeout:3) {tab.tap()}else{app.staticTexts["My projects"].tap()}}
    }
    func testOwnPreviewFiltersEndedAndOtherBusinessType() {launch();XCTAssertTrue(app.buttons["profile.selfProjects.project.topic:7"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["profile.selfProjects.project.activity:7"].exists);XCTAssertFalse(app.buttons["profile.selfProjects.project.topic:8"].exists)}
    func testTopicDetailAndBackKeepUsablePreview() {launch();app.buttons["profile.selfProjects.project.topic:7"].tap();XCTAssertTrue(app.staticTexts["profile.selfProjectsFixture.detail"].waitForExistence(timeout:5));app.navigationBars.buttons.element(boundBy:0).tap();XCTAssertTrue(app.buttons["profile.selfProjects.project.topic:7"].waitForExistence(timeout:5))}
    func testFailureRetryReturnsGenuineRows() {launch("failure");let retry=app.buttons["profile.selfProjects.retry"];XCTAssertTrue(retry.waitForExistence(timeout:5));retry.tap();XCTAssertTrue(app.buttons["profile.selfProjects.project.topic:7"].waitForExistence(timeout:5))}
    func testRefreshFailureRetainsDisabledRowsThenRecovers() {launch("refreshFailure");app.buttons["profile.selfProjects.refresh"].tap();XCTAssertTrue(app.staticTexts["profile.selfProjects.issue"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["profile.selfProjects.project.topic:7"].isEnabled);app.buttons["profile.selfProjects.retry"].tap();XCTAssertTrue(app.buttons["profile.selfProjects.project.topic:7"].isEnabled)}
    func testAllProjectsIncludesEndedAndActivityRows() {launch();app.buttons["profile.selfProjects.all"].tap();XCTAssertTrue(app.buttons["creatorContent.project.activity:7"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["creatorContent.project.topic:8"].exists)}
    func testTruncationAndEmptyHaveDifferentTruthfulStates() {launch("truncated");XCTAssertTrue(app.staticTexts["profile.selfProjects.truncated"].waitForExistence(timeout:5));app.terminate();launch("empty");XCTAssertTrue(app.staticTexts["profile.selfProjects.empty"].waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["profile.selfProjects.issue"].exists)}
    func testGuestAndOtherMemberMakeNoPrivateReads() {for scenario in ["guest","other"] {launch(scenario,open:false);XCTAssertEqual(app.staticTexts["profile.selfProjectsFixture.reads"].label,"Projects reads: 0");XCTAssertFalse(app.buttons["profile.selfProjects.all"].exists);app.terminate()}}
}
