import XCTest

/// Offline 我的收藏 topic unlike (w2-03). A synthetic transport answers; nothing leaves the device.
final class TopicUnlikeFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func openTopics(_ scenario: String, language: String = "en") {
        app.launchArguments = ["--uitesting-member-parity", "--member-parity-page", "favorites", "--member-parity-scenario", scenario,
                               "--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        let tabs = app.segmentedControls["accountCollection.favorites.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons.element(boundBy: 1).tap()
    }
    func testConfirmedUnlikeRemovesTheTopic() {
        openTopics("ready", language: "zh-Hans")
        let heart = app.buttons["member.unlike.301"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10)); heart.tap()
        XCTAssertTrue(app.alerts.staticTexts["确定要取消点赞吗？"].waitForExistence(timeout: 5))
        app.alerts.buttons["确定"].tap()
        XCTAssertTrue(app.staticTexts["取消点赞成功"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["accountCollection.favorite.301"].exists)
    }
    func testCancelKeepsTheTopic() {
        openTopics("ready")
        let heart = app.buttons["member.unlike.301"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10)); heart.tap()
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["accountCollection.favorite.301"].exists)
    }
    func testLostResponseRequiresCheckBeforeAnyRetry() {
        openTopics("unknown")
        let heart = app.buttons["member.unlike.302"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10)); heart.tap()
        app.alerts.buttons["Confirm"].tap()
        let check = app.buttons["member.unlike.check"]
        XCTAssertTrue(check.waitForExistence(timeout: 5)); check.tap()
        XCTAssertTrue(app.staticTexts["Couldn't unlike. Please try again."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accountCollection.favorite.302"].exists)
    }
    func testDormantBuildShowsNoUnlikeControl() {
        openTopics("dormant")
        XCTAssertTrue(app.buttons["accountCollection.favorite.301"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["member.unlike.301"].exists)
    }
}
