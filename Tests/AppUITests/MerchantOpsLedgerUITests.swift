import XCTest

/// Offline ledger parity (source pages/merchant/ledger/index.*) through the merchant business fixture.
final class MerchantOpsLedgerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting-reset-language", "--uitesting-merchant-business-fixture", "--uitesting-merchant-business-scenario", "ready",
                                "-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_US"]
        app.launch(); return app
    }
    private func open(_ identifier: String, _ app: XCUIApplication) {
        let button = app.buttons[identifier]
        for _ in 0..<10 { if button.waitForExistence(timeout: 0.3) && button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 3), app.debugDescription); button.tap()
    }
    func testRedemptionRowShowsReadableStateAndPendingAmount() {
        let app = launch(); open("merchant.business.open.redemptions", app)
        let row = app.buttons["merchant.business.row.redemption.redemption:64001"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row.label.contains("Pending theme settlement"), row.label)
        XCTAssertTrue(row.label.contains("Example route · Example chapter"), row.label)
        XCTAssertFalse(row.label.contains("PENDING_SETTLEMENT"), row.label)
    }
    func testBatchRowShowsReconcilingState() {
        let app = launch(); open("merchant.business.open.batches", app)
        let row = app.buttons["merchant.business.row.batch.66001"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row.label.contains("Awaiting reconciliation"), row.label)
    }
    func testBatchDetailShowsNetHero() {
        let app = launch(); open("merchant.business.open.batches", app)
        open("merchant.business.row.batch.66001", app)
        let hero = app.descendants(matching: .any)["merchantOps.ledger.batchHero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(hero.label.contains("2026-09 batch net"), hero.label)
    }
    func testRedemptionDetailShowsIncomeHero() {
        let app = launch(); open("merchant.business.open.redemptions", app)
        open("merchant.business.row.redemption.redemption:64001", app)
        let hero = app.descendants(matching: .any)["merchantOps.ledger.redemptionHero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(hero.label.contains("My income"), hero.label)
    }
}
