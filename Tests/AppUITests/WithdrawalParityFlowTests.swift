import XCTest

/// w2-05 offline parity journeys for tixian / tixianjilu. DEBUG fixture only; runtime NOT_RUN on Linux.
final class WithdrawalParityFlowTests: XCTestCase {
    private func launch(_ scenario: String = "rows") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--wallet-commerce-fixture", "--withdrawal-parity=" + scenario,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); app.buttons["wallet.fixture.withdrawalParity"].tap(); return app
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    func testHistoryRowsUseReceivedAmountAndSourceStatusMapping() {
        let app = launch(); app.buttons["withdrawal.parity.history"].tap()
        let processing = element(app, "withdrawal.history.row.50")
        XCTAssertTrue(processing.waitForExistence(timeout: 5))
        XCTAssertTrue(processing.label.contains("-12.30")); XCTAssertTrue(processing.label.contains("Withdrawal in progress"))
        XCTAssertTrue(element(app, "withdrawal.history.row.52").label.contains("full amount was returned"))
        XCTAssertTrue(element(app, "withdrawal.history.row.53").label.contains("Status unconfirmed"))
        XCTAssertTrue(element(app, "withdrawal.history.row.54").label.contains("—"))
        XCTAssertFalse(element(app, "withdrawal.history.failed").exists)
    }
    func testEmptyHistoryIsExplicit() {
        let app = launch("empty"); app.buttons["withdrawal.parity.history"].tap()
        XCTAssertTrue(element(app, "withdrawal.history.empty").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "withdrawal.history.retry").exists)
    }
    func testDeniedAndSignedOutHaveNoRetryOrEmptySuccess() {
        for (scenario, id) in [("denied", "withdrawal.history.denied"), ("unauthorized", "withdrawal.history.login")] {
            let app = launch(scenario); app.buttons["withdrawal.parity.history"].tap()
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 5), scenario)
            XCTAssertFalse(element(app, "withdrawal.history.retry").exists)
            XCTAssertFalse(element(app, "withdrawal.history.empty").exists)
            app.terminate()
        }
    }
    func testFailureOffersRetryWithoutRows() {
        let app = launch("failure"); app.buttons["withdrawal.parity.history"].tap()
        XCTAssertTrue(element(app, "withdrawal.history.failed").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["withdrawal.history.retry"].exists)
        XCTAssertFalse(element(app, "withdrawal.history.row.50").exists)
    }
    func testApplicationPageNamesOfflineSupportAndOpensHistory() {
        let app = launch(); app.buttons["withdrawal.parity.apply"].tap()
        let contact = app.buttons["withdrawal.apply.contact"]
        if !contact.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(contact.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "withdrawal.apply.method").exists)
        contact.tap()
        XCTAssertTrue(app.buttons["withdrawal.support.close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["withdrawal.support.copyWeChat"].exists)
        app.buttons["withdrawal.support.close"].tap()
        let history = app.buttons["withdrawal.apply.history"]
        if !history.waitForExistence(timeout: 3) { app.swipeUp() }
        history.tap()
        XCTAssertTrue(element(app, "withdrawal.history.row.50").waitForExistence(timeout: 5))
    }
}
