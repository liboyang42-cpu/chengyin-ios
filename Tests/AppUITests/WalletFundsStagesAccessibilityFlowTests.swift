import XCTest

/// Existing offline wallet fixtures only. No production financial operation.
final class WalletFundsStagesAccessibilityFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--wallet-commerce-fixture", "--wallet-earnings-overview-fixture",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + flags
        app.launch()
        app.buttons["wallet.fixture.income"].tap()
        return app
    }
    func testUnknownStageKeepsLeafIdentityWithoutInventingZero() {
        let app = launch(); defer { app.terminate() }
        let unknown = app.staticTexts["wallet.earnings.stages.unknown"]
        XCTAssertTrue(unknown.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(unknown.label, "—")
        XCTAssertEqual(app.staticTexts.matching(identifier: "wallet.earnings.stages.unknown").count, 1)
        XCTAssertFalse(app.staticTexts["wallet.earnings.stages.available"].exists)
        XCTAssertFalse(app.staticTexts["wallet.earnings.stages.failed"].exists)
        XCTAssertFalse(app.buttons["wallet.earnings.stages.retry"].exists)
        XCTAssertFalse(app.staticTexts["wallet.earnings.stages"].exists)
    }
    func testFailedStageRetainsRetryActionAndIndependentIncomeRow() {
        let app = launch(["--wallet-assets-recover"]); defer { app.terminate() }
        let retry = app.buttons["wallet.earnings.stages.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "wallet.earnings.stages.retry").count, 1)
        XCTAssertFalse(app.buttons["wallet.earnings.stages"].exists)
        XCTAssertTrue(app.buttons["wallet.income.detail.open.4"].exists)
        XCTAssertTrue(retry.isEnabled && retry.isHittable)
        retry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["wallet.earnings.stages.available"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["wallet.earnings.stages.retry"].exists)
        XCTAssertTrue(app.buttons["wallet.income.detail.open.4"].exists)
    }
    func testUnconfiguredStageDoesNotBecomeRetryOrKnownZero() {
        let app = launch(["--wallet-assets-denied"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["wallet.earnings.stages.unconfigured"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["wallet.earnings.stages.retry"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["wallet.earnings.stages.available"].exists)
        XCTAssertTrue(app.buttons["wallet.income.detail.open.4"].exists)
    }
    func testKnownZeroRemainsDistinctFromUnknown() {
        let app = launch(["--wallet-assets-known-zero"]); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["wallet.earnings.stages.empty"].waitForExistence(timeout: 5), app.debugDescription)
        let available = app.descendants(matching: .any)["wallet.earnings.stages.available"]
        XCTAssertTrue(available.exists)
        XCTAssertTrue((available.value as? String ?? available.label).contains("0"))
        XCTAssertFalse(app.staticTexts["wallet.earnings.stages.unknown"].exists)
        XCTAssertFalse(app.staticTexts["wallet.earnings.stages.failed"].exists)
    }

}
