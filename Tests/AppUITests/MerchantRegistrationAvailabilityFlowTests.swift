import XCTest

final class MerchantRegistrationAvailabilityFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(revealFixtureElement(button, in: app, towardTop: id == "merchant.registrationAvailability.open" || id == "merchant.registrationAvailability.restore")); button.tap()
    }
    private func open() -> XCUIApplication {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-content-fixture"]
        app.launch(); tap("merchant.content.entry.registrations", app); tap("merchant.content.open.registration", app); tap("merchant.content.edit", app)
        return app
    }
    func testCancelAndRestorePreserveOriginalUnrecognizedSource() {
        let app = open(); tap("merchant.registrationAvailability.open", app)
        XCTAssertTrue(app.buttons["merchant.registrationAvailability.apply"].waitForExistence(timeout: 4))
        tap("merchant.registrationAvailability.cancel", app)
        XCTAssertFalse(app.buttons["merchant.registrationAvailability.restore"].exists)
        tap("merchant.registrationAvailability.open", app); tap("merchant.registrationAvailability.apply", app)
        XCTAssertTrue(revealFixtureElement(app.descendants(matching: .any)["merchant.registrationAvailability.newDaily"].firstMatch, in: app, requiresHittable: false))
        tap("merchant.registrationAvailability.restore", app)
        XCTAssertFalse(app.buttons["merchant.registrationAvailability.restore"].exists)
        XCTAssertTrue(app.staticTexts["source civil time"].exists)
    }
    func testGroupReviewCancelAndExistingSaveReadBackServerValues() {
        let app = open(); tap("merchant.registrationAvailability.open", app); tap("merchant.registrationAvailability.apply", app)
        tap("merchant.content.review", app)
        XCTAssertTrue(revealFixtureElement(app.descendants(matching: .any)["merchant.registrationAvailability.review"].firstMatch, in: app, requiresHittable: false))
        tap("merchant.content.review.cancel", app)
        XCTAssertTrue(revealFixtureElement(app.buttons["merchant.registrationAvailability.restore"], in: app))
        tap("merchant.content.review", app); tap("merchant.content.confirm", app)
        XCTAssertTrue(app.staticTexts["merchant.content.issue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["merchant.content.issue"].label, "Availability was refreshed from the saved registration.")
        XCTAssertFalse(app.buttons["merchant.registrationAvailability.restore"].exists)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["09:00-18:00"].firstMatch, in: app, requiresHittable: false))
        attachFixtureScreenshot(self, app: app, name: "Synthetic registration availability source readback")
    }
    func testBackgroundDiscardsOnlyUnappliedAvailabilitySheet() {
        let app = open(); tap("merchant.registrationAvailability.open", app)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.buttons["merchant.registrationAvailability.apply"].exists)
        XCTAssertFalse(app.buttons["merchant.registrationAvailability.restore"].exists)
        tap("merchant.registrationAvailability.open", app)
        XCTAssertTrue(app.buttons["merchant.registrationAvailability.apply"].waitForExistence(timeout: 5))
    }
}
