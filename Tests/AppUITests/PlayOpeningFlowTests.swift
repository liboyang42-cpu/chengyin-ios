import XCTest

/// Offline opening-chapter 出发 flow with a synthetic route state. Apple execution is unrun here.
final class PlayOpeningFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playOpening", "--play-opening-scenario", scenario,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        runningApp = app; app.launch(); return app
    }

    func testNotReadyAsksToFinishOpeningPlayFirst() {
        let app = app("notReady")
        XCTAssertTrue(app.buttons["playx.opening.depart"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["playx.opening.depart"].tap()
        XCTAssertTrue(app.staticTexts["请先完成开局玩法"].waitForExistence(timeout: 5))
    }

    func testDepartNeedsConfirmationAndLostResponseIsCheckedNotResent() {
        let app = app("lost")
        XCTAssertTrue(app.buttons["playx.opening.depart"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["playx.opening.depart"].tap()
        XCTAssertTrue(app.buttons["playx.opening.confirm"].waitForExistence(timeout: 5))
        app.buttons["playx.opening.confirm"].tap()
        let done = app.staticTexts["playx.opening.departed"]
        let unknown = app.buttons["playx.opening.readBack"]
        XCTAssertTrue(done.waitForExistence(timeout: 5) || unknown.exists, app.debugDescription)
        if unknown.exists { unknown.tap(); XCTAssertTrue(done.waitForExistence(timeout: 5)) }
        XCTAssertFalse(app.buttons["playx.opening.depart"].exists)
    }
}
