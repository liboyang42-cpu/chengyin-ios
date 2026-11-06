import XCTest

/// mylike 已加载全部主题 after the last page (w2-03), synthetic favorites fixture.
final class FavoritesEndOfListFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    func testTopicsShowEndTextOnlyAfterTheLastPage() {
        app.launchArguments = ["--uitesting-member-parity", "--member-parity-page", "favorites", "--member-parity-scenario", "dormant",
                               "--uitesting-reset-language", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let tabs = app.segmentedControls["accountCollection.favorites.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10)); tabs.buttons.element(boundBy: 1).tap()
        let more = app.buttons["accountCollection.favorites.loadMore"]
        for _ in 0..<12 where !more.exists { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["已加载全部主题"].exists)
        more.tap()
        let end = app.staticTexts["已加载全部主题"]
        for _ in 0..<6 where !end.exists { app.swipeUp() }
        XCTAssertTrue(end.waitForExistence(timeout: 5))
    }
}
