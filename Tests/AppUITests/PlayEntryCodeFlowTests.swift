import XCTest

/// Offline 入场码 entry in play: missing-ticket explanation and the gated ticket path. Apple execution is unrun here.
final class PlayEntryCodeFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playEntryCode", "--play-entry-code-scenario", scenario,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        runningApp = app; app.launch(); return app
    }

    func testWithoutRegistrationExplainsAndOffersTicketWallet() {
        let app = app("missing")
        let open = app.buttons["playx.entryCode.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        open.tap()
        XCTAssertTrue(app.alerts["从票夹进入才能出示入场码"].waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons["去票夹"].tap()
        XCTAssertTrue(app.staticTexts["playx.entryCode.fixtureWallet"].waitForExistence(timeout: 5))
    }

    func testTicketPathStaysDisabledWithoutInjectedIssuer() {
        let app = app("ticket")
        let open = app.buttons["playx.entryCode.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        open.tap()
        XCTAssertTrue(app.staticTexts["verificationCode.disabled"].waitForExistence(timeout: 5), app.debugDescription)
    }
}
