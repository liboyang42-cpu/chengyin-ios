import XCTest

/// userinfo header 好友 count (w2-03), shown with the other counters; unknown stays "—".
final class PublicProfileFriendsFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    func testAchievementsListFriendsNextToFollowers() {
        app.launchArguments = ["--uitesting-profile-self-growth", "--profile-self-growth-scenario", "content",
                               "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic growth owner"].waitForExistence(timeout: 10))
        let picker = app.buttons["social.profile.tabs"]; if picker.exists { picker.tap() }
        let tab = app.buttons["Achievements"]; if tab.waitForExistence(timeout: 3) { tab.tap() } else { app.staticTexts["Achievements"].tap() }
        let friends = app.descendants(matching: .any)["social.profile.friends"]
        for _ in 0..<6 where !friends.exists { app.swipeUp() }
        XCTAssertTrue(friends.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Friends"].exists)
    }
}
