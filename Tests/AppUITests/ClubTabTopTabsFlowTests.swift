import XCTest

/// Source talent/list 帖文 / 俱乐部 top tabs. Offline fixtures only; authored, requires simulator execution.
final class ClubTabTopTabsFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }

    func testOpensOnClubsAndSwitchesToPostsAndBack() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "--uitesting-club-fixture", "owner", "--uitesting-club-top-tabs"]
        app.launch()
        let clubs = app.buttons["俱乐部"], posts = app.buttons["帖文"]
        XCTAssertTrue(clubs.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(clubs.isSelected)
        XCTAssertTrue(app.buttons["club.openDirectory"].waitForExistence(timeout: 10))
        posts.tap()
        XCTAssertTrue(posts.isSelected)
        XCTAssertFalse(app.buttons["club.openDirectory"].exists)
        clubs.tap()
        XCTAssertTrue(app.buttons["club.openDirectory"].waitForExistence(timeout: 5))
    }

    func testTopTabsHiddenWithoutCommunity() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-club-fixture", "owner"]
        app.launch()
        XCTAssertTrue(app.buttons["club.openDirectory"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.segmentedControls["clubTab.topTabs"].exists)
    }
}
