import XCTest

/// Offline retired circle link: missing topic state and redirect parameters. Apple execution is unrun here.
final class PlayCircleLegacyLinkFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ query: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playCircleLink", "--play-circle-link-query", query,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        runningApp = app; app.launch(); return app
    }

    func testMissingTopicShowsIncompleteLinkAndGoesHome() {
        let app = app("inviteCode=AB12")
        XCTAssertTrue(app.staticTexts["探索链接不完整"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["请从圈层主题或同行人分享的邀请重新进入"].exists)
        app.buttons["playx.circleLink.home"].tap()
        XCTAssertTrue(app.staticTexts["playx.circleLink.fixtureHome"].waitForExistence(timeout: 5))
    }

    func testTopicLinkCarriesInviteAndRegistration() {
        let app = app("topicId=12&inviteCode=AB12&registrationId=88")
        XCTAssertTrue(app.staticTexts["playx.circleLink.redirect.topic"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["playx.circleLink.redirect.invite"].label, "invite AB12")
        XCTAssertEqual(app.staticTexts["playx.circleLink.redirect.registration"].label, "registration 88")
    }
}
