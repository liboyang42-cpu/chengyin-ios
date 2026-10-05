import XCTest

/// Authored Apple-host tests. Requires DEBUG --public-merchant-home-fixture <scenario> host hook.
final class PublicMerchantHomeFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func launch(_ scenario: String, language: String = "en", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting-reset-language", "-AppleLanguages", "(\(language))",
                                "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                                "--public-merchant-home-fixture", scenario]
        if largeText { app.launchArguments.append("--uitesting-large-text") }
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
    func testFeaturedActivityUsesExactIDAfterBackAndUnavailableDetail() {
        let app = launch("featured-activity")
        XCTAssertTrue(app.staticTexts["Synthetic featured walk"].waitForExistence(timeout: 5))
        let open = app.buttons["merchant.publicHome.featured.open"]
        for _ in 0..<2 {
            reveal(open, in: app); open.tap()
            XCTAssertTrue(app.staticTexts["Synthetic activity 601"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["merchant.publicHome.chat"].exists)
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.staticTexts["Fixture shop"].waitForExistence(timeout: 5))
        }
        app.terminate()
        let unavailable = launch("featured-unavailable")
        let link = unavailable.buttons["merchant.publicHome.featured.open"]
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(unavailable.staticTexts["Merchant does not exist or is not open to the public"].waitForExistence(timeout: 5))
        unavailable.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(unavailable.staticTexts["Fixture shop"].waitForExistence(timeout: 5))
    }
    func testFeaturedCouponOpensWalletWithoutOwnedIDOrCodeInChineseLargeText() {
        let app = launch("featured-coupon", language: "zh-Hans", largeText: true)
        XCTAssertTrue(app.staticTexts["Synthetic featured coupon"].waitForExistence(timeout: 5))
        let open = app.buttons["merchant.publicHome.featured.open"]
        reveal(open, in: app)
        XCTAssertEqual(open.label, "查看我的券夹")
        XCTAssertFalse(app.staticTexts["主推活动图片"].exists)
        open.tap()
        XCTAssertTrue(app.staticTexts["merchant.featured.fixture.wallet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["couponCode.open"].exists)
        XCTAssertFalse(app.buttons["couponCode.review"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic activity 901"].exists)
    }
    func testMissingUnknownAndMalformedFeaturedCardsLeaveProfileUsable() {
        for scenario in ["featured-null", "featured-unknown", "featured-malformed", "featured-missing-identity", "featured-mismatched-owner"] {
            let app = launch(scenario)
            XCTAssertTrue(app.staticTexts["Fixture shop"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["Should not appear"].exists)
            XCTAssertFalse(app.buttons["merchant.publicHome.featured.open"].exists)
            XCTAssertFalse(app.staticTexts["Synthetic featured walk"].exists)
            if scenario != "featured-missing-identity" { XCTAssertTrue(app.buttons["merchant.publicHome.reviews"].exists) }
            app.terminate()
        }
        let app = launch("featured-static")
        XCTAssertTrue(app.staticTexts["Synthetic featured walk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["merchant.publicHome.featured.open"].exists)
    }
    func testFeaturedSelectionClosesWhenReadScopeChangesThenUsesNewSnapshot() {
        let app = launch("featured-switch")
        let open = app.buttons["merchant.publicHome.featured.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        XCTAssertTrue(app.staticTexts["Synthetic activity 601"].waitForExistence(timeout: 5))
        app.buttons["merchant.featured.fixture.changeScope"].tap()
        XCTAssertTrue(app.staticTexts["Fixture shop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic activity 601"].exists)
        reveal(open, in: app); open.tap()
        XCTAssertTrue(app.staticTexts["Synthetic activity 602"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic activity 601"].exists)
    }

}
