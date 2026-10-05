import XCTest
final class ClubOwnerRefundFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: runningApp)
        runningApp?.terminate(); runningApp = nil
    }
    private func launch(_ fixture: String, language: String = "en") -> XCUIApplication {
        checkFixtureBounds()
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-club-governance", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]; app.launch()
        tap(fixture, app); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let isFixtureControl = id == "club.refund.fixtureRecord" || id == "club.refund.fixtureSwitch"
        let isNavigationControl = id == "club.refund.cancel"
        let button = isNavigationControl ? app.navigationBars.buttons[id]
            : app.buttons[id]
        if isFixtureControl || isNavigationControl {
            // Exact fixture footer and navigation actions sit outside scrolling content.
            XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        } else {
            XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        }
        if isFixtureControl {
            XCTAssertEqual(app.buttons.matching(identifier: id).count, 1, app.debugDescription)
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(fixtureControlFits(button.frame, in: app.frame,
                keyboard: keyboard.exists ? keyboard.frame : nil), app.debugDescription)
        }
        XCTAssertTrue(button.exists, app.debugDescription)
        XCTAssertTrue(button.isEnabled, app.debugDescription)
        XCTAssertTrue(button.isHittable, app.debugDescription); button.tap()
    }
    private func fixtureControlFits(_ frame: CGRect, in appFrame: CGRect, keyboard: CGRect?) -> Bool {
        guard !frame.isEmpty, !frame.isNull, !frame.isInfinite,
              !appFrame.isEmpty, !appFrame.isNull, !appFrame.isInfinite,
              appFrame.contains(frame) else { return false }
        return keyboard.map { !$0.intersects(frame) } ?? true
    }
    private func checkFixtureBounds() {
        let appFrame = CGRect(x: 0, y: 0, width: 420, height: 912)
        let visible = CGRect(x: 16, y: 800, width: 388, height: 44)
        XCTAssertTrue(fixtureControlFits(visible, in: appFrame, keyboard: nil))
        XCTAssertFalse(fixtureControlFits(CGRect(x: -12.7, y: 842, width: 224, height: 36), in: appFrame, keyboard: nil))
        XCTAssertFalse(fixtureControlFits(CGRect(x: 225.3, y: 842, width: 207.3, height: 36), in: appFrame, keyboard: nil))
        XCTAssertFalse(fixtureControlFits(.zero, in: appFrame, keyboard: nil))
        XCTAssertFalse(fixtureControlFits(visible, in: appFrame, keyboard: CGRect(x: 0, y: 700, width: 420, height: 212)))
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
