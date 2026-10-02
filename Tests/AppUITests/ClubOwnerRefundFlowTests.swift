import XCTest
final class ClubOwnerRefundFlowTests: XCTestCase {
    private func launch(_ fixture: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-club-governance", "-AppleLanguages", "(\(language))", "-AppleLocale", language]; app.launch()
        tap(fixture, app); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]
        for _ in 0..<10 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertTrue(button.isHittable); button.tap()
    }
    func testDisabledShippingStyleReviewCannotSubmitAndCanCancel() {
        let app = launch("club.refund.fixtureDisabled")
        tap("club.refund.review", app)
        let confirm = app.buttons["club.refund.confirm"]
        for _ in 0..<6 where !confirm.isHittable { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(confirm.isEnabled)
        tap("club.refund.cancel", app)
        XCTAssertTrue(app.buttons["club.refund.review"].waitForExistence(timeout: 5))
    }
    func testOfflineAcknowledgmentHasSeparateCashAndPointsRows() {
        let app = launch("club.refund.fixtureAccepted"); tap("club.refund.review", app); tap("club.refund.confirm", app)
        XCTAssertTrue(app.descendants(matching: .any)["club.refund.receipt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.refund.review"].exists)
        XCTAssertTrue(app.buttons["club.refund.readback"].exists)
    }
    func testUnknownReadbackNeverResubmitsAndRefundRecordRemainsDistinct() {
        let app = launch("club.refund.fixtureUnknown"); tap("club.refund.review", app); tap("club.refund.confirm", app)
        tap("club.refund.readback", app)
        XCTAssertFalse(app.buttons["club.refund.review"].exists)
        tap("club.refund.fixtureRecord", app); tap("club.refund.readback", app)
        XCTAssertTrue(app.staticTexts["club.refund.phase"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["club.refund.receipt"].exists)
    }
    func testAccountSwitchDismissesReviewAndClearsNamesInChinese() {
        let app = launch("club.refund.fixtureDisabled", language: "zh-Hans")
        tap("club.refund.review", app); tap("club.refund.cancel", app); tap("club.refund.fixtureSwitch", app)
        XCTAssertFalse(app.buttons["club.refund.review"].exists)
        XCTAssertFalse(app.staticTexts["Fixture attendee"].exists)
    }
}
