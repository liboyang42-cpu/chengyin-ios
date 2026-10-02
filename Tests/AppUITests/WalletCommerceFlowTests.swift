import XCTest

/// Requires DEBUG host registration documented in integration.md. Runtime NOT_RUN on Linux.
final class WalletCommerceFlowTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--wallet-commerce-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch(); return app
    }
    func testFundsStagesUnknownCurrencyAndZeroRemainDistinct() {
        let app = launch(); app.buttons["wallet.fixture.assets"].tap()
        XCTAssertTrue(app.staticTexts["Available to withdraw"].waitForExistence(timeout: 5))
        // LabeledContent may expose the amount together with its row label.
        let zeroAmount = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label ENDSWITH %@", "0 currency unspecified", ", 0 currency unspecified")).firstMatch
        XCTAssertTrue(zeroAmount.exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Some amounts cannot be calculated yet. Final settlement applies"].exists)
    }
    func testCheckoutIsPreviewAndCannotRedeem() {
        let app = launch(); app.buttons["wallet.fixture.cart"].tap()
        let row = app.switches["wallet.cart.20"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let nativeSwitch = row.switches.firstMatch
        if nativeSwitch.exists { nativeSwitch.tap() }
        else { row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, app.debugDescription)
        let preview = app.buttons["Checkout preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription); preview.tap()
        XCTAssertTrue(app.staticTexts["wallet.previewOnly"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Place order"].exists)
        XCTAssertFalse(app.buttons["Pay"].exists)
    }
    func testApprovalIsNotFinalPayoutAndBankAccountIsMasked() {
        let app = launch(); app.buttons["wallet.fixture.withdrawals"].tap()
        XCTAssertTrue(app.staticTexts["wallet.withdrawal.40"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["SYNTHETIC-1234"].exists)
        XCTAssertFalse(app.buttons["Withdraw"].exists)
    }
    func testFailureOffersRetryWithoutInventedZero() {
        let app = launch(["--wallet-failure"]); app.buttons["wallet.fixture.assets"].tap()
        XCTAssertTrue(app.staticTexts["wallet.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["0 currency unspecified"].exists)
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.staticTexts["wallet.issue"].exists)
    }
    func testSignOutHidesAccountData() {
        let app = launch(); app.buttons["wallet.fixture.signOut"].tap()
        app.buttons["wallet.fixture.points"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to view this information"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["wallet.ledger.3"].exists)
    }
    func testBankFormIsReachableAndClearlyDormant() {
        let app = launch(); app.buttons["wallet.fixture.bankWithdrawal"].tap()
        XCTAssertTrue(app.staticTexts["Bank-card submission is not enabled in this build. No banking details will be sent."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["bank.withdrawal.account"].exists)
        XCTAssertFalse(app.buttons["bank.withdrawal.confirmSubmit"].exists)
    }
    func testBankReviewValidatesBeforeOpeningConfirmation() {
        let app = launch(); app.buttons["wallet.fixture.bankWithdrawal"].tap()
        let review = app.buttons["bank.withdrawal.review"]
        if !review.isHittable { app.swipeUp() }
        review.tap()
        XCTAssertTrue(app.staticTexts["bank.withdrawal.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["bank.withdrawal.prepare"].exists)
    }
    func testBankHistoryUsesServerRejectedStatusInsteadOfPaid() {
        let app = launch(); app.buttons["wallet.fixture.withdrawals"].tap()
        let row = app.staticTexts["wallet.withdrawal.41"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Rejected"))
        XCTAssertFalse(row.label.contains("Paid"))
    }

}
