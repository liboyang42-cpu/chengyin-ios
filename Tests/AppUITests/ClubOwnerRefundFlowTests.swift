import XCTest
final class ClubOwnerRefundFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: runningApp)
        runningApp?.terminate(); runningApp = nil
    }
    private func launch(_ fixture: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-club-governance", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]; app.launch()
        tap(fixture, app); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let isToolbarControl = id == "club.refund.fixtureRecord" || id == "club.refund.fixtureSwitch"
        let isNavigationControl = id == "club.refund.cancel"
        let button = isNavigationControl ? app.navigationBars.buttons[id]
            : (isToolbarControl ? app.toolbars.buttons[id] : app.buttons[id])
        if isToolbarControl || isNavigationControl {
            // Bar actions live outside the scrollable content viewport.
            XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        } else {
            XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        }
        XCTAssertTrue(button.exists, app.debugDescription)
        XCTAssertTrue(button.isEnabled, app.debugDescription)
        XCTAssertTrue(button.isHittable, app.debugDescription); button.tap()
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
        let cancellation = app.descendants(matching: .any)["club.refund.receipt"].firstMatch
        XCTAssertTrue(cancellation.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(cancellation.value as? String, "Cancelled")
        let cash = app.descendants(matching: .any)["club.refund.cashStatus"].firstMatch
        let points = app.descendants(matching: .any)["club.refund.pointsStatus"].firstMatch
        XCTAssertTrue(cash.exists); XCTAssertTrue(points.exists)
        XCTAssertEqual(cash.value as? String, "Channel processing")
        XCTAssertEqual(points.value as? String, "No points used")
        XCTAssertFalse(app.buttons["club.refund.review"].exists)
        XCTAssertTrue(app.buttons["club.refund.readback"].exists)
    }
    func testUnknownReadbackNeverResubmitsAndRefundRecordRemainsDistinct() {
        let app = launch("club.refund.fixtureUnknown"); tap("club.refund.review", app); tap("club.refund.confirm", app)
        tap("club.refund.readback", app)
        XCTAssertFalse(app.buttons["club.refund.review"].exists)
        tap("club.refund.fixtureRecord", app); tap("club.refund.readback", app)
        XCTAssertTrue(app.staticTexts["club.refund.phase"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["club.refund.receipt"].firstMatch.exists)
    }
    func testAccountSwitchDismissesReviewAndClearsNamesInChinese() {
        let app = launch("club.refund.fixtureDisabled", language: "zh-Hans")
        tap("club.refund.review", app); tap("club.refund.cancel", app); tap("club.refund.fixtureSwitch", app)
        XCTAssertFalse(app.buttons["club.refund.review"].exists)
        XCTAssertFalse(app.staticTexts["Fixture attendee"].exists)
    }
}
