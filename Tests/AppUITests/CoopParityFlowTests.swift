import XCTest

/// Offline coverage for the coop parity pages (profit share details, settlement detail, withdraw shells).
/// Uses the synthetic --cooperation-flow-fixture host; no live transport, payment or withdrawal.
final class CoopParityFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }

    func testFinanceKeepsUnknownIncomeUnwithdrawableAndOpensHostDetail() {
        let app = launch()
        app.buttons["coopflow.route.coopflow.finance"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cooperation.finance.stat.income"].waitForExistence(timeout: 5), app.debugDescription)
        let withdraw = app.buttons["cooperation.finance.withdraw"]
        XCTAssertTrue(withdraw.exists); XCTAssertFalse(withdraw.isEnabled)
        XCTAssertTrue(app.staticTexts["Credited amount awaiting confirmation"].exists)
        app.buttons["coopflow.settlement.finance.8"].tap()
        XCTAssertTrue(app.navigationBars["Settlement details"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Organizer profit share"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["cooperation.settlement.step.hostUnsettled"].exists)
    }

    func testFinanceDeniedShowsPermissionState() {
        let app = launch(denied: true)
        app.buttons["coopflow.route.coopflow.finance"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cooperation.finance.issue.denied"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["cooperation.finance.withdraw"].exists)
    }

    func testWithdrawNoticeOffersOnlySupportContactInChinese() {
        let app = launch(language: "zh-Hans")
        let entry = app.buttons["cooperation.withdraw.open"]
        XCTAssertTrue(revealFixtureElement(entry, in: app), app.debugDescription); entry.tap()
        XCTAssertTrue(app.staticTexts["提现方式已调整"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["cooperation.withdraw.contact"].exists)
        XCTAssertFalse(app.textFields.firstMatch.exists)
    }

    private func launch(language: String = "en", denied: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting-reset-language", "--cooperation-flow-fixture", "-AppleLanguages", "(\(language))",
                                "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if denied { app.launchArguments += ["--cooperation-flow-denied"] }
        app.launch(); self.app = app
        XCTAssertTrue(app.descendants(matching: .any)["coopflow.workbench"].waitForExistence(timeout: 5), app.debugDescription)
        return app
    }
}
