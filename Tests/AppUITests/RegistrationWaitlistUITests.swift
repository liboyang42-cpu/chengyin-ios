import XCTest

final class RegistrationWaitlistUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-registration-fixture", scenario]
        app.launch()
        XCTAssertTrue(app.navigationBars["Activity registration"].waitForExistence(timeout: 10))
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testWaitingAndLeavingRemainInTheRegistrationForm() {
        launch("waitlistWaiting")
        let join = app.buttons["registration.waitlist.join"]; reveal(join); join.tap()
        let cancel = app.buttons["registration.waitlist.cancel"]; reveal(cancel)
        XCTAssertTrue(app.staticTexts["Waiting for an available place"].exists, app.debugDescription)
        capture("Waitlist waiting in native registration form – synthetic")
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Waitlist entry cancelled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["registration.form.readStatus"].exists)
        XCTAssertTrue(app.navigationBars["Activity registration"].exists)
    }
    func testOfferRequiresNewConsentAndCancelledReviewDoesNotCreate() {
        launch("waitlistOffer")
        let offer = app.buttons["registration.waitlist.reviewOffer"]; reveal(offer); offer.tap()
        let consent = app.switches["registration.form.consent"]; reveal(consent)
        XCTAssertEqual(consent.value as? String, "0", app.debugDescription)
        let control = consent.switches.firstMatch; (control.exists ? control : consent).tap()
        let review = app.buttons["registration.form.review"]; reveal(review)
        XCTAssertTrue(review.isEnabled); review.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["registration.form.readStatus"].exists)
        capture("Waitlist offer review cancelled – synthetic")
        app.buttons["registration.form.close"].tap()
        app.buttons["registration.fixture.open"].tap()
        XCTAssertTrue(app.navigationBars["Activity registration"].waitForExistence(timeout: 5))
        reveal(app.buttons["registration.waitlist.reviewOffer"])
        XCTAssertFalse(app.buttons["registration.form.readStatus"].exists)
    }
}
