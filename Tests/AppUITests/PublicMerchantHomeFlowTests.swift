import XCTest

/// Authored Apple-host tests. Requires DEBUG --public-merchant-home-fixture <scenario> host hook.
final class PublicMerchantHomeFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--public-merchant-home-fixture", scenario]
        app.launch(); return app
    }
    func testInvalidLinkHasNoRetry() {
        let app = launch("invalid")
        XCTAssertTrue(app.staticTexts["merchant.publicHome.invalid"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["merchant.publicHome.retry"].exists)
    }
    func testUnavailableIsNotRetryable() {
        let app = launch("unavailable")
        XCTAssertTrue(app.staticTexts["merchant.publicHome.unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["merchant.publicHome.retry"].exists)
    }
    func testRetryRecoversAndReviewsUseBothReturnedIDs() {
        let app = launch("retry")
        let retry = app.buttons["merchant.publicHome.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(app.staticTexts["Fixture shop"].waitForExistence(timeout: 5))
        let reviews = app.buttons["merchant.publicHome.reviews"]
        XCTAssertTrue(reviews.exists); reviews.tap()
        XCTAssertTrue(app.staticTexts["Fixture review"].waitForExistence(timeout: 5))
    }
    func testMissingReturnedOwnerCannotOpenReviews() {
        let app = launch("missing-ids")
        XCTAssertTrue(app.staticTexts["Fixture shop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["merchant.publicHome.reviews"].exists)
        XCTAssertFalse(app.buttons["merchant.publicHome.chat"].exists)
    }
    func testNPCStaticIdentityDoesNotActivateChat() {
        let app = launch("profile")
        XCTAssertTrue(app.staticTexts["Fixture guide"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["merchant.publicHome.chat"].exists)
    }
    func testReportRequiresReviewThenReturnsModerationReceipt() {
        let app = launch("profile")
        let reviews = app.buttons["merchant.publicHome.reviews"]
        XCTAssertTrue(reviews.waitForExistence(timeout: 5)); reviews.tap()
        let report = app.buttons["merchant.publicHome.report.9"]
        XCTAssertTrue(app.staticTexts["Fixture review"].waitForExistence(timeout: 5), app.debugDescription)
        reveal(report, in: app); report.tap()
        let text = app.textViews["merchant.publicHome.editorText"]
        if text.exists { text.tap(); text.typeText("Fixture report reason") }
        else { let field = app.textFields["merchant.publicHome.editorText"]; field.tap(); field.typeText("Fixture report reason") }
        app.buttons["merchant.publicHome.prepare"].tap()
        let confirm = app.buttons["merchant.publicHome.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let status = app.descendants(matching: .any)["merchant.publicHome.status"].firstMatch
        reveal(status, in: app)
        XCTAssertEqual(status.value as? String, "PENDING_PLATFORM_REVIEW", app.debugDescription)
        XCTAssertFalse(app.buttons["merchant.publicHome.confirm"].exists)
        XCTAssertFalse(app.staticTexts["merchant.publicHome.unknown"].exists)
        XCTAssertFalse(app.staticTexts["merchant.publicHome.writeFailure"].exists)
    }
}
