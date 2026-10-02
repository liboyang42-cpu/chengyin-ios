import XCTest

/// Requires DEBUG host registration documented in integration.md. Runtime NOT_RUN on Linux.
final class WalletCommerceFlowTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--wallet-commerce-fixture", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch(); return app
    }
    func testFundsStagesUnknownCurrencyAndZeroRemainDistinct() {
        let app = launch(); app.buttons["wallet.fixture.assets"].tap()
        XCTAssertTrue(app.staticTexts["Available to withdraw"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 currency unspecified"].exists)
        XCTAssertTrue(app.staticTexts["Some amounts cannot be calculated yet. Final settlement applies"].exists)
    }
    func testCheckoutIsPreviewAndCannotRedeem() {
        let app = launch(); app.buttons["wallet.fixture.cart"].tap()
        let row = app.switches["wallet.cart.20"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        app.buttons["Checkout preview"].tap()
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
}
