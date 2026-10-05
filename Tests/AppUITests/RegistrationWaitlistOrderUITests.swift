import XCTest

final class RegistrationWaitlistOrderUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String, language: String = "en") {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-registration-fixture", scenario]
        app.launch()
    }
    private func openOrder() {
        let button = app.buttons["registration.waitlist.openOrder"]
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        button.tap()
    }
    func testClaimedAndConvertedOrderReadbackCloseAndReopenInBothLanguages() {
        for language in ["en", "zh-Hans"] {
            for scenario in ["waitlistClaimed", "waitlistConverted"] {
                launch(scenario, language: language)
                openOrder()
                let orderNumber = language == "en" ? "Order number, OFFLINE-WAITLIST-9417" : "订单号、OFFLINE-WAITLIST-9417"
                XCTAssertTrue(app.staticTexts[orderNumber].waitForExistence(timeout: 5), app.debugDescription)
                // Even CONVERTED never replaces the authoritative detail payment facts.
                XCTAssertFalse(app.buttons["registration.form.readStatus"].exists)
                app.buttons["registration.waitlist.order.close"].tap()
                openOrder()
                XCTAssertTrue(app.staticTexts[orderNumber].waitForExistence(timeout: 5), app.debugDescription)
                app.buttons["registration.waitlist.order.close"].tap()
                let review = app.buttons["registration.form.review"]
                XCTAssertTrue(revealFixtureElement(review, in: app)); XCTAssertFalse(review.isEnabled)
                app.terminate()
            }
        }
    }
    func testOrderReadErrorRetryAndCloseDoNotCreateReplacement() {
        launch("waitlistOrderError"); openOrder()
        let retry = app.buttons["profile.order.detail.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        app.buttons["registration.waitlist.order.close"].tap()
        openOrder(); XCTAssertTrue(retry.waitForExistence(timeout: 5))
    }
}
