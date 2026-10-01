import XCTest

/// Integration requires ModuleFixture.ticketWallet -> TicketWalletFixtureHostView.
final class TicketWalletFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content") {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "ticketWallet", "--uitesting-ticket-wallet-scenario", scenario]
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<6 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
    func testWalletDetailEntitlementsBackAndReopenNeverOffersCodeOrPayment() {
        launch()
        let row = app.buttons["ticketWallet.row.901"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.navigationBars["Ticket details"].waitForExistence(timeout: 5))
        let pending = app.descendants(matching: .any)["ticketWallet.pendingChapters"]
        reveal(pending)
        XCTAssertTrue(app.staticTexts["Sample pending chapter"].exists)
        reveal(app.descendants(matching: .any)["ticketWallet.redemption.notice"])
        XCTAssertTrue(app.staticTexts["Redemption codes are not available in this native version yet"].exists)
        XCTAssertFalse(app.buttons["Show redemption code"].exists)
        XCTAssertFalse(app.buttons["Pay"].exists)
        app.navigationBars["Ticket details"].buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.staticTexts["Sample exploration ticket"].waitForExistence(timeout: 5))
    }
    func testPartialEmptyIsNotReportedAsCompleteEmptyWallet() {
        launch("partialEmpty")
        XCTAssertTrue(app.staticTexts["Activity tickets could not be loaded"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No tickets were returned by the available source. The wallet may be incomplete."].exists)
        XCTAssertFalse(app.staticTexts["Your ticket wallet is empty"].exists)
        app.buttons["ticketWallet.retry"].tap()
        XCTAssertTrue(app.staticTexts["Activity tickets could not be loaded"].waitForExistence(timeout: 5))
    }
    func testUnavailableDetailRetryDoesNotShowCachedContent() {
        launch("unavailable")
        XCTAssertTrue(app.staticTexts["This ticket is unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Sample exploration ticket"].exists)
        app.buttons["ticketWallet.retry"].tap()
        XCTAssertTrue(app.staticTexts["This ticket is unavailable"].waitForExistence(timeout: 5))
    }
    func testRefreshReadsCurrentStatusInsteadOfKeepingTheOldTicket() {
        launch("refreshed")
        XCTAssertTrue(app.staticTexts["Sample exploration ticket"].waitForExistence(timeout: 10))
        app.buttons["ticketWallet.detail.refresh"].tap()
        XCTAssertTrue(app.staticTexts["Sample cancelled after refresh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample exploration ticket"].exists)
        XCTAssertFalse(app.staticTexts["Sample pending chapter"].exists)
    }
    func testSignOutClearsDetailAndReturnsToLoginGate() {
        launch("sessionChange")
        let row = app.buttons["ticketWallet.row.901"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.navigationBars["Ticket details"].waitForExistence(timeout: 5))
        app.buttons["ticketWallet.fixture.signOut"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to see your tickets"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample exploration ticket"].exists)
        XCTAssertFalse(app.staticTexts["Sample pending chapter"].exists)
    }
    func testEmptyFailureGuestAndConfigurationStatesAreDistinct() {
        for (scenario, message) in [("empty", "Your ticket wallet is empty"), ("failure", "Tickets could not be loaded"), ("guest", "Sign in to see your tickets"), ("unconfigured", "Ticket service is not configured")] {
            launch(scenario)
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 10), "Scenario: \(scenario)")
            if scenario != "empty" { XCTAssertFalse(app.staticTexts["Your ticket wallet is empty"].exists) }
            XCTAssertFalse(app.staticTexts["Sample exploration ticket"].exists)
            app.terminate()
        }
    }
}
