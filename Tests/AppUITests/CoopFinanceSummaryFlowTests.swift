import XCTest

/// 主办分润 summary on the existing --cooperation-flow-fixture (w2-03); synthetic data only.
final class CoopFinanceSummaryFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    func testSummaryShowsCreditedZeroAndUnknownAdjustmentsAsDash() {
        app.launchArguments += ["--uitesting-reset-language", "--cooperation-flow-fixture", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["coopflow.workbench"].waitForExistence(timeout: 10))
        app.buttons["coopflow.route.coopflow.finance"].tap()
        XCTAssertTrue(app.staticTexts["已入账分润"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["¥0.00"].exists)
        XCTAssertTrue(app.staticTexts["调整待处理"].exists)
        XCTAssertTrue(app.staticTexts["已结算不等于已入账：已结算表示金额完成核算，已入账表示款项已进入个人账户。"].exists)
        XCTAssertTrue(app.buttons["coopflow.settlement.finance.8"].exists)
    }
}
