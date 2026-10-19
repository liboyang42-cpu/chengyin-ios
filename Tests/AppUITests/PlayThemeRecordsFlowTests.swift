import XCTest

/// Offline 我的游玩记录 / 本局结果 with synthetic pages. Apple execution is unrun here.
final class PlayThemeRecordsFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playThemeRecords", "--play-theme-records-scenario", scenario,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        runningApp = app; app.launch(); return app
    }

    func testHistoryOpensResultCardAndRetriesFailedCard() {
        let app = app("content")
        let first = app.buttons["playx.themeRecords.row.900"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(first.label.contains("本局完成"), first.label)
        XCTAssertTrue(app.buttons["playx.themeRecords.row.899"].label.contains("本局结束"))
        first.tap()
        XCTAssertTrue(app.staticTexts["Lighthouse reached"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["下次场景：Fish market"].exists)
        app.buttons["playx.themeRecords.closeCard"].tap()
        app.buttons["playx.themeRecords.row.899"].tap()
        XCTAssertTrue(app.buttons["playx.themeRecords.retryCard"].waitForExistence(timeout: 5))
        app.buttons["playx.themeRecords.retryCard"].tap()
        XCTAssertTrue(app.staticTexts["Lighthouse reached"].waitForExistence(timeout: 5))
    }

    func testEmptyAndFailureStates() {
        let empty = app("empty")
        XCTAssertTrue(empty.staticTexts["还没有游玩记录"].waitForExistence(timeout: 10), empty.debugDescription)
        empty.terminate()
        let failed = app("failure")
        XCTAssertTrue(failed.staticTexts["游玩记录暂未加载，请稍后重试"].waitForExistence(timeout: 10), failed.debugDescription)
        XCTAssertTrue(failed.buttons["playx.themeRecords.more"].exists)
    }
}
