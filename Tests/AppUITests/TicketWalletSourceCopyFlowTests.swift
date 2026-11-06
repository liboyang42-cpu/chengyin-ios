import XCTest

/// w2-04 signup parity copy over the existing offline ticket-wallet fixture scenarios.
final class TicketWalletSourceCopyFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "ticketWallet", "--uitesting-ticket-wallet-scenario", scenario]
        app.launch()
    }
    func testTrueEmptyShowsSourceHintWithoutFailureTitle() {
        launch("empty")
        XCTAssertTrue(app.staticTexts["ticketWallet.empty"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ticketWallet.emptyHint"].exists)
        XCTAssertFalse(app.staticTexts["ticketWallet.errorTitle"].exists)
    }
    func testFullFailureShowsSourceTitleAboveReasonAndRetry() {
        launch("failure")
        XCTAssertTrue(app.staticTexts["ticketWallet.errorTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Tickets could not be loaded"].exists)
        XCTAssertTrue(app.buttons["ticketWallet.retry"].exists)
        XCTAssertFalse(app.staticTexts["ticketWallet.emptyHint"].exists)
    }
    func testPartialEmptyNeverShowsTrueEmptyHint() {
        launch("partialEmpty")
        XCTAssertTrue(app.staticTexts["Activity tickets could not be loaded"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["ticketWallet.emptyHint"].exists)
        XCTAssertFalse(app.staticTexts["ticketWallet.errorTitle"].exists)
    }
}
