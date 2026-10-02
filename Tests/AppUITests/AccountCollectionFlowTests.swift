import XCTest

/// Root integration: ModuleFixture.accountCollections -> AccountCollectionFixtureHostView.
/// All cases are synthetic and offline; no API base URL or credentials are configured.
final class AccountCollectionFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", language: String = "en", extra: [String] = []) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-module", "accountCollections", "--uitesting-account-collection-scenario", scenario] + extra
        app.launch()
    }
    private func open(_ id: String) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        button.tap()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
    func testFavoritePaginationRoutesToRealTopicAndReturnsToSavedCollection() {
        launch()
        open("accountCollection.openFavorites")
        XCTAssertTrue(app.buttons["accountCollection.favorite.301"].waitForExistence(timeout: 10))
        attachFixtureScreenshot(self, app: app, name: "Favorite topic full-bleed cards")
        let more = app.buttons["accountCollection.favorites.loadMore"]
        reveal(more); more.tap()
        XCTAssertTrue(app.buttons["accountCollection.favorite.303"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "accountCollection.favorite.301").count, 1)
        let topic = app.buttons["accountCollection.favorite.303"]
        reveal(topic); topic.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Route details"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["This coupon is no longer available"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5))
    }
    func testLaterPageFailureKeepsRowsAndRetryReadsSamePage() {
        launch("pageFailure"); open("accountCollection.openFavorites")
        let more = app.buttons["accountCollection.favorites.loadMore"]
        reveal(more); more.tap()
        XCTAssertTrue(app.staticTexts["Sample next page unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accountCollection.favorite.301"].exists)
        let retry = app.buttons["accountCollection.retry"]
        reveal(retry); retry.tap()
        XCTAssertTrue(app.buttons["accountCollection.favorite.303"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample next page unavailable"].exists)
    }
    func testCouponFiltersMetadataDetailBackAndReopen() {
        launch(); open("accountCollection.openCoupons")
        let row = app.buttons["accountCollection.coupon.701"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        attachFixtureScreenshot(self, app: app, name: "Owned coupon collection")
        row.tap()
        XCTAssertTrue(app.navigationBars["Coupon details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample weekend benefit"].waitForExistence(timeout: 5))
        let notice = app.staticTexts["accountCollection.coupon.readOnly"]
        reveal(notice)
        XCTAssertTrue(app.staticTexts["Read-only coupon details. Redemption codes are not available here yet."].exists)
        XCTAssertFalse(app.buttons["Show code"].exists); XCTAssertFalse(app.buttons["Redeem"].exists)
        XCTAssertFalse(app.images["qrcode"].exists)
        attachFixtureScreenshot(self, app: app, name: "Read-only coupon detail")
        app.navigationBars["Coupon details"].buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.staticTexts["Sample weekend benefit"].waitForExistence(timeout: 5))
    }
    func testCouponFilterMenuUsesServerStatus() {
        launch(); open("accountCollection.openCoupons")
        XCTAssertTrue(app.buttons["accountCollection.coupon.701"].waitForExistence(timeout: 10))
        let filter = app.buttons["accountCollection.coupons.filter"]
        XCTAssertTrue(filter.exists, app.debugDescription); filter.tap()
        app.buttons["Used"].tap()
        XCTAssertTrue(app.buttons["accountCollection.coupon.702"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["accountCollection.coupon.701"].exists)
        XCTAssertFalse(app.buttons["accountCollection.coupon.704"].exists)
    }
    func testCouponFailureDoesNotPoisonFavorites() {
        launch("couponFailure"); open("accountCollection.openCoupons")
        XCTAssertTrue(app.staticTexts["Sample coupons source unavailable"].waitForExistence(timeout: 10))
        app.navigationBars["My coupons"].buttons.firstMatch.tap()
        open("accountCollection.openFavorites")
        XCTAssertTrue(app.buttons["accountCollection.favorite.301"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Sample coupons source unavailable"].exists)
    }
    func testCouponDetailRefreshReplacesStatusWithoutCachedCode() {
        launch("refreshed")
        XCTAssertTrue(app.staticTexts["Sample weekend benefit"].waitForExistence(timeout: 10))
        open("accountCollection.coupon.detail.refresh")
        XCTAssertTrue(app.staticTexts["Sample invalid after refresh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample weekend benefit"].exists)
        XCTAssertTrue(app.staticTexts["Invalid"].exists)
    }
    func testUnavailableCouponHasRetryAndNoOldDetail() {
        launch("unavailable")
        XCTAssertTrue(app.staticTexts["This coupon is no longer available"].waitForExistence(timeout: 10))
        open("accountCollection.retry")
        XCTAssertTrue(app.staticTexts["This coupon is no longer available"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample weekend benefit"].exists)
    }
    func testGuestEmptyFailureAndConfigurationAreDistinct() {
        for (scenario, expected) in [("guest", "Sign in to see your saved collections"), ("empty", "No coupons yet"), ("failure", "These items could not be loaded"), ("unconfigured", "Collection service is not configured")] {
            launch(scenario); open("accountCollection.openCoupons")
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 10), scenario)
            XCTAssertFalse(app.staticTexts["Sample weekend benefit"].exists)
            if scenario != "empty" { XCTAssertFalse(app.staticTexts["No coupons yet"].exists) }
            app.terminate()
        }
    }
    func testSessionChangeClearsPrivateCouponDetailAndFavorites() {
        launch("sessionChange"); open("accountCollection.openCoupons"); open("accountCollection.coupon.701")
        XCTAssertTrue(app.staticTexts["Sample weekend benefit"].waitForExistence(timeout: 5))
        open("accountCollection.fixture.signOut")
        XCTAssertFalse(app.staticTexts["Sample weekend benefit"].exists)
        open("accountCollection.openFavorites")
        XCTAssertTrue(app.staticTexts["Sign in to see your saved collections"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["accountCollection.favorite.301"].exists)
    }
    func testChineseFavoritesAndCouponNavigation() {
        launch(language: "zh-Hans")
        open("accountCollection.openFavorites")
        XCTAssertTrue(app.navigationBars["我的收藏"].waitForExistence(timeout: 5))
        app.navigationBars["我的收藏"].buttons.firstMatch.tap()
        open("accountCollection.openCoupons")
        XCTAssertTrue(app.navigationBars["我的优惠券"].waitForExistence(timeout: 5))
        open("accountCollection.coupon.701")
        XCTAssertTrue(app.navigationBars["优惠券详情"].waitForExistence(timeout: 5))
    }
    func testLargeTypeDarkModeKeepsCardsAndCouponDetailsReachable() {
        launch(extra: ["--uitesting-dark", "--uitesting-large-text"])
        open("accountCollection.openFavorites")
        let favorite = app.buttons["accountCollection.favorite.301"]
        reveal(favorite)
        XCTAssertGreaterThanOrEqual(favorite.frame.height, 44)
        attachFixtureScreenshot(self, app: app, name: "Favorite card large text dark mode")
        app.navigationBars["Favorites"].buttons.firstMatch.tap()
        open("accountCollection.openCoupons")
        let coupon = app.buttons["accountCollection.coupon.701"]
        reveal(coupon); coupon.tap()
        reveal(app.staticTexts["accountCollection.coupon.readOnly"])
        attachFixtureScreenshot(self, app: app, name: "Coupon detail large text dark mode")
    }

}
