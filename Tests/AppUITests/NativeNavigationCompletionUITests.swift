import XCTest

final class NativeNavigationCompletionUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments += ["--native-navigation-fixture", mode, "-AppleLanguages", "(en)"]
        app.launch(); return app
    }
    func testGlobalFallbackHasHomeAndCloseWithoutRawRoute() {
        let app = launch("error")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "nativeNav.error").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nativeNav.error.close"].exists)
        XCTAssertTrue(app.buttons["nativeNav.error.home"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'GoException'")).firstMatch.exists)
    }
    func testCouponReviewPrecedesSyntheticQRCode() {
        let app = launch("coupon")
        let review = app.buttons["couponCode.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5)); XCTAssertFalse(app.images["couponCode.qr"].exists)
        review.tap()
        let confirm = app.sheets.buttons["Show code"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(app.images["couponCode.qr"].exists)
        confirm.tap()
        XCTAssertTrue(app.images["couponCode.qr"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic coupon"].exists)
    }
    func testPlayerScanManualInputIsExplicitAndCancellable() {
        let app = launch("player")
        let open = app.buttons["playerEvidence.open.701"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let field = app.textFields["playerEvidence.manual"]
        XCTAssertTrue(revealFixtureElement(field, in: app)); field.tap(); field.typeText("SYNTHETIC-CODE")
        let manualReview = app.buttons["playerEvidence.manual.review"]
        XCTAssertTrue(revealFixtureElement(manualReview, in: app)); XCTAssertTrue(manualReview.isEnabled)
        app.buttons["Close"].tap(); XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap(); XCTAssertTrue(revealFixtureElement(field, in: app))
        XCTAssertFalse((field.value as? String)?.contains("SYNTHETIC-CODE") == true)
        XCTAssertTrue(revealFixtureElement(manualReview, in: app, requiresHittable: false))
        XCTAssertFalse(manualReview.isEnabled)
    }
    func testBadgeSourceQueryEntryIsReachableFromNormalWall() {
        let app = launch("badge")
        XCTAssertTrue(app.buttons["Open badge link"].waitForExistence(timeout: 5)); app.buttons["Open badge link"].tap()
        let field = app.textFields["nativeNav.badge.path"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("/badge?name=Synthetic%20badge&rarity=2")
        app.buttons["Open"].tap(); XCTAssertTrue(app.staticTexts["Synthetic badge"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap(); XCTAssertTrue(field.waitForExistence(timeout: 5))
    }
}
