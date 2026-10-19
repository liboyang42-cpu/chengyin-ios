import XCTest

/// Offline read-only backpack (背包): values, items, clues and the unavailable 任务 tab. Apple execution is unrun here.
final class PlayThemeBackpackFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playBackpack", "--play-backpack-scenario", scenario,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testItemsCluesAndTasksTabs() {
        let app = app("content")
        XCTAssertTrue(element("playx.backpack.load", app).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("playx.backpack.value.hp", app).label.contains("7 / 10"))
        XCTAssertTrue(element("playx.backpack.item.tea", app).label.contains("Herbal tea"))
        XCTAssertTrue(element("playx.backpack.item.map", app).label.contains("Old map"))
        let tabs = app.segmentedControls["playx.backpack.tabs"]
        tabs.buttons["线索"].tap()
        XCTAssertTrue(app.staticTexts["Harbour rumour"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["全场公开"].exists)
        tabs.buttons["任务"].tap()
        XCTAssertTrue(element("playx.backpack.gameUnavailable", app).waitForExistence(timeout: 5))
    }

    func testZeroHPAndFailureStates() {
        let zero = app("zero")
        XCTAssertTrue(element("playx.backpack.zeroHP", zero).waitForExistence(timeout: 10), zero.debugDescription)
        XCTAssertTrue(zero.staticTexts["步行恢复"].exists)
        zero.terminate()
        let failed = app("failure")
        XCTAssertTrue(element("playx.backpack.failed", failed).waitForExistence(timeout: 10), failed.debugDescription)
        XCTAssertTrue(failed.buttons["playx.backpack.retry"].exists)
    }
}
