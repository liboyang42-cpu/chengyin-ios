import XCTest

final class NativeNavigationCompletionUITests: XCTestCase {
    private func launch(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments += ["--native-navigation-fixture", mode, "-AppleLanguages", "(en)"]
        app.launch(); return app
    }
    func testGlobalFallbackHasHomeAndCloseWithoutRawRoute() {
        let app = launch("error")
        XCTAssertTrue(app.otherElements["nativeNav.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Close"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'GoException'")).firstMatch.exists)
    }
    func testCouponReviewPrecedesSyntheticQRCode() {
        let app = launch("coupon"), review = XCUIApplication().buttons["couponCode.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5)); XCTAssertFalse(app.images["couponCode.qr"].exists)
        review.tap(); app.buttons["Show code"].tap()
        XCTAssertTrue(app.images["couponCode.qr"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic coupon"].exists)
    }
    func testPlayerScanManualInputIsExplicitAndCancellable() {
        let app = launch("player"), open = XCUIApplication().buttons["playerEvidence.open.701"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let field = app.textViews["playerEvidence.manual"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("SYNTHETIC-CODE")
        XCTAssertTrue(app.buttons["playerEvidence.manual.review"].isEnabled)
        app.buttons["Close"].tap(); XCTAssertTrue(open.waitForExistence(timeout: 5))
    }
    func testBadgeSourceQueryEntryIsReachableFromNormalWall() {
        let app = launch("badge")
        XCTAssertTrue(app.buttons["Open badge link"].waitForExistence(timeout: 5)); app.buttons["Open badge link"].tap()
        let field = app.textViews["nativeNav.badge.path"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("/badge?name=Synthetic%20badge&rarity=2")
        app.buttons["Open"].tap(); XCTAssertTrue(app.staticTexts["Synthetic badge"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap(); XCTAssertTrue(field.waitForExistence(timeout: 5))
    }
}
