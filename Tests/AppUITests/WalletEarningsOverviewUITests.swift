import XCTest

/// DEBUG fixture only. Compile, simulator, and device runs are NOT_RUN on Linux.
final class WalletEarningsOverviewUITests: XCTestCase {
    private func waitForLabel(_ element: XCUIElement, _ value: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)
    }

    private func launch(_ extra: [String] = [], language: String = "en", locale: String = "en_US") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--wallet-commerce-fixture", "--wallet-earnings-overview-fixture",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", locale] + extra
        app.launch()
        return app
    }

    func testIncomeTabOpensBillDetailAndBackDoesNotLeaveTheEarningsScreen() {
        let app = launch()
        app.buttons["wallet.fixture.income"].tap()
        let row = app.buttons["wallet.income.detail.open.4"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let close = app.buttons["wallet.income.detail.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["wallet.earnings.tab.income"].exists)
        XCTAssertTrue(app.buttons["wallet.earnings.tab.organizer"].exists)
    }

    func testOrganizerTabReadsSummaryOnceAndReturnsFromSettlementDetail() {
        let app = launch()
        app.buttons["wallet.fixture.income"].tap()
        let reads = app.staticTexts["wallet.earnings.finance.reads"]
        XCTAssertTrue(reads.waitForExistence(timeout: 5))
        XCTAssertEqual(reads.label, "0")
        app.buttons["wallet.earnings.tab.organizer"].tap()
        let settlement = app.buttons["coopflow.settlement.finance.8"]
        XCTAssertTrue(settlement.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["coopflow.summary.credited"].waitForExistence(timeout: 5))
        waitForLabel(reads, "1")
        XCTAssertTrue(app.staticTexts["Awaiting credit"].exists || settlement.label.contains("Awaiting credit"))
        XCTAssertFalse(app.staticTexts["Credited"].exists)
        XCTAssertTrue(app.staticTexts["wallet.earnings.finance.separate"].exists)
        settlement.tap()
        XCTAssertTrue(app.staticTexts["Awaiting credit"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(settlement.waitForExistence(timeout: 5))
        // The shared reader may refresh when navigation returns. Verify content, not a fixed read count.
        XCTAssertTrue(app.descendants(matching: .any)["coopflow.summary.credited"].exists)
        app.buttons["wallet.earnings.tab.income"].tap()
        XCTAssertTrue(app.buttons["wallet.income.detail.open.4"].waitForExistence(timeout: 5))
        app.buttons["wallet.earnings.tab.organizer"].tap()
        XCTAssertTrue(settlement.exists)
    }

    func testClosedOrganizerTabShowsUnconfiguredAndDoesNotRead() {
        let app = launch(["--wallet-earnings-finance-denied"])
        app.buttons["wallet.fixture.income"].tap()
        app.buttons["wallet.earnings.tab.organizer"].tap()
        XCTAssertTrue(app.staticTexts["wallet.earnings.finance.unconfigured"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coopflow.settlement.finance.8"].exists)
        XCTAssertEqual(app.staticTexts["wallet.earnings.finance.reads"].label, "0")
        app.buttons["wallet.earnings.tab.income"].tap()
        XCTAssertTrue(app.buttons["wallet.income.detail.open.4"].waitForExistence(timeout: 5))
    }

    func testUnknownStagesShowUnknownAndKnownZeroStaysZero() {
        let unknown = launch()
        unknown.buttons["wallet.fixture.income"].tap()
        let label = unknown.staticTexts["wallet.earnings.stages.unknown"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertEqual(label.label, "Unknown")
        XCTAssertFalse(unknown.staticTexts["wallet.earnings.stages.available"].exists)
        XCTAssertFalse(unknown.staticTexts["wallet.earnings.stages.failed"].exists)
        unknown.terminate()
        let zero = launch(["--wallet-assets-known-zero"])
        zero.buttons["wallet.fixture.income"].tap()
        XCTAssertTrue(zero.staticTexts["wallet.earnings.stages.empty"].waitForExistence(timeout: 5))
        let available = zero.staticTexts["wallet.earnings.stages.available"]
        XCTAssertTrue(available.exists)
        XCTAssertTrue(available.label.contains("0"))
        XCTAssertFalse(zero.staticTexts["wallet.earnings.stages.unknown"].exists)
        XCTAssertFalse(zero.staticTexts["wallet.earnings.stages.failed"].exists)
    }

    func testUnconfiguredStagesHaveNoRetryAndATransientFailureRetriesAlone() {
        let denied = launch(["--wallet-assets-denied"])
        denied.buttons["wallet.fixture.income"].tap()
        XCTAssertTrue(denied.staticTexts["wallet.earnings.stages.unconfigured"].waitForExistence(timeout: 5))
        XCTAssertFalse(denied.buttons["wallet.earnings.stages.retry"].exists)
        XCTAssertTrue(denied.buttons["wallet.income.detail.open.4"].waitForExistence(timeout: 5))
        denied.terminate()
        let failed = launch(["--wallet-assets-recover"])
        failed.buttons["wallet.fixture.income"].tap()
        let retry = failed.buttons["wallet.earnings.stages.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertTrue(failed.buttons["wallet.income.detail.open.4"].exists)
        retry.tap()
        XCTAssertTrue(failed.staticTexts["wallet.earnings.stages.available"].waitForExistence(timeout: 5))
        XCTAssertFalse(failed.staticTexts["wallet.earnings.stages.failed"].exists)
    }

    func testChineseLabelsAndLargeTextKeepTheRealValues() {
        let app = launch(language: "zh-Hans", locale: "zh_Hans_CN")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        app.terminate(); app.launch()
        app.buttons["wallet.fixture.income"].tap()
        let organizer = app.buttons["wallet.earnings.tab.organizer"]
        XCTAssertTrue(organizer.waitForExistence(timeout: 5))
        XCTAssertEqual(organizer.label, "主办分润")
        XCTAssertGreaterThanOrEqual(organizer.frame.height, 44)
        let unknown = app.staticTexts["wallet.earnings.stages.unknown"]
        XCTAssertEqual(unknown.label, "未知")
        app.terminate()
        let zero = launch(["--wallet-assets-known-zero"], language: "zh-Hans", locale: "zh_Hans_CN")
        zero.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        zero.terminate(); zero.launch()
        zero.buttons["wallet.fixture.income"].tap()
        let available = zero.staticTexts["wallet.earnings.stages.available"]
        XCTAssertTrue(available.waitForExistence(timeout: 5))
        XCTAssertTrue(available.label.contains("0"))
        XCTAssertFalse(available.label.contains("未知"))
    }
}
