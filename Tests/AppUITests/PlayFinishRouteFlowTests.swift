import XCTest

/// Offline 附近下一程 card on the finish sheet. Apple execution is unrun here.
final class PlayFinishRouteFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playFinishRoute", "--play-finish-route-scenario", scenario,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        runningApp = app; app.launch()
        XCTAssertTrue(app.staticTexts["playx.finishRoute.fixture"].waitForExistence(timeout: 10), app.debugDescription)
        return app
    }

    func testCardSkipsCurrentRouteAndOpensActivity() {
        let app = app("content")
        let card = app.buttons["playx.finishRoute.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(card.label.contains("Harbour lights walk"), card.label)
        XCTAssertTrue(card.label.contains("1.3 公里 · Pier 3"), card.label)
        XCTAssertTrue(card.label.contains("¥39 起"), card.label)
        card.tap()
        XCTAssertTrue(app.staticTexts["playx.finishRoute.destination"].waitForExistence(timeout: 5))
    }

    func testFlagOffOrSameTopicShowsNoCard() {
        for scenario in ["disabled", "sameTopic", "noOrigin"] {
            let app = app(scenario)
            XCTAssertFalse(app.buttons["playx.finishRoute.card"].waitForExistence(timeout: 2), scenario)
            app.terminate()
        }
    }
}
