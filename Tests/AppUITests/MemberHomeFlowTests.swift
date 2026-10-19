import XCTest

/// Offline 我的 header and 当前权益 (w2-03). Synthetic data only.
final class MemberHomeFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String, language: String = "en") {
        app.launchArguments = ["--uitesting-member-parity", "--member-parity-page", "home", "--member-parity-scenario", scenario,
                               "--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
    }
    func testReadyCardShowsServerCountsCityAndBenefits() {
        launch("ready")
        XCTAssertTrue(app.staticTexts["Synthetic member"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["member.card.following"].waitForExistence(timeout: 5) || app.staticTexts["12"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic City"].exists)
        let earnings = app.buttons["member.benefit.earnings"]
        XCTAssertTrue(earnings.waitForExistence(timeout: 5))
        earnings.tap()
        XCTAssertTrue(app.staticTexts["member.fixture.earnings"].waitForExistence(timeout: 5))
    }
    func testFailedReadOffersReloadWithoutInventedCounts() {
        launch("failure")
        let retry = app.buttons["member.card.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Synthetic account"].exists)
        XCTAssertFalse(app.staticTexts["12"].exists)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Synthetic member"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["member.benefits.retry"].exists)
    }
    func testDormantBuildExplainsUnavailableStateInChinese() {
        launch("dormant", language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["当前配置暂不能读取权益。"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Synthetic account"].exists)
        XCTAssertFalse(app.buttons["member.card.retry"].exists)
    }
    func testTicketButtonOpensTicketWallet() {
        launch("ready")
        let tickets = app.buttons["member.card.tickets"]
        XCTAssertTrue(tickets.waitForExistence(timeout: 10))
        tickets.tap()
        XCTAssertTrue(app.alerts["Synthetic ticket wallet"].waitForExistence(timeout: 5))
    }
}
