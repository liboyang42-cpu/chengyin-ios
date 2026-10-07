import XCTest

/// Synthetic normal list → fresh detail → explicit short-lived code review. No real grant or redemption.
final class OwnedCouponCodeJourneyUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        button.tap()
    }
    private func assertIssues(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let value = app.staticTexts["ownedCoupon.fixture.issueCount"]
        XCTAssertTrue(value.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(value.label, String(count), file: file, line: line)
    }
    func testOwnedListDetailCancelConfirmBackAndReopenRequireFreshConsent() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "accountCollections", "--uitesting-account-collection-scenario", "codePresentation"]
        app.launch(); assertIssues(0)
        tap("accountCollection.openCoupons"); tap("accountCollection.coupon.701")
        let detailArrived = app.navigationBars["Coupon details"].waitForExistence(timeout: 5)
        var detailDiagnostic = ""
        if !detailArrived {
            let expectedExists = app.navigationBars["Coupon details"].exists
            let allowedTitles: Set<String> = ["Collections", "My coupons", "Coupons", "Coupon details", "Ticket wallet", "Show code"]
            let titles = app.navigationBars.allElementsBoundByIndex.prefix(4).map { bar in
                let value = bar.identifier
                return allowedTitles.contains(value) ? value : "other"
            }
            let sheets = app.sheets.count
            detailDiagnostic = "OWNED_COUPON_NAV AFTER_TIMEOUT_ONLY expectedExists=\(expectedExists) titles=\(titles) sheets=\(sheets)"
        }
        XCTAssertTrue(detailArrived, detailDiagnostic)
        XCTAssertTrue(app.staticTexts["Sample weekend benefit"].waitForExistence(timeout: 5)); assertIssues(0)
        tap("couponCode.open")
        XCTAssertTrue(app.buttons["couponCode.review"].waitForExistence(timeout: 5)); assertIssues(0)
        XCTAssertFalse(app.images["couponCode.qr"].exists)
        tap("couponCode.review")
        let confirm = app.sheets.buttons["Show code"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); assertIssues(0)
        app.sheets.buttons["Cancel"].tap()
        XCTAssertFalse(app.images["couponCode.qr"].exists); assertIssues(0)
        tap("couponCode.review"); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.images["couponCode.qr"].waitForExistence(timeout: 5)); assertIssues(1)
        XCTAssertTrue(app.staticTexts["Offline current merchant terms"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Coupon details"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.images["couponCode.qr"].exists); assertIssues(1)
        tap("couponCode.open")
        XCTAssertTrue(app.buttons["couponCode.review"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.images["couponCode.qr"].exists); assertIssues(1)
        attachFixtureScreenshot(self, app: app, name: "Owned coupon reopened with fresh review and no retained code")
    }
}
