import XCTest

/// Offline 账户收益 / 收益明细 presentation pieces (w2-03).
final class WalletEarningsParityFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    func testChineseRelativeDaysAndZeroEarningsCopy() {
        app.launchArguments = ["--uitesting-member-parity", "--member-parity-page", "earnings",
                               "--uitesting-reset-language", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.staticTexts["今天"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["昨天"].exists)
        XCTAssertTrue(app.staticTexts["12月31日"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["wallet.earnings.empty"].exists)
    }
}
