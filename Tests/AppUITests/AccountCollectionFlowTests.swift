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
    private func open(_ id: String, diagnoseNavigation: Bool = false) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        if diagnoseNavigation { logNavigationBoundary("before single tap", target: button, identifier: id) }
        button.tap()
        if diagnoseNavigation { logNavigationBoundary("after single tap", target: button, identifier: id) }
    }
    // This module is synthetic and offline. Log only the selected control and
    // navigation bars; image-only CI evidence does not retain AX attachments.
    private func logNavigationBoundary(_ phase: String, target: XCUIElement, identifier: String) {
        let exists = target.exists
        print("ACCOUNT_COLLECTION_NAVIGATION phase=\(phase); identifier=\(identifier); type=\(exists ? String(target.elementType.rawValue) : "absent"); exists=\(exists); enabled=\(exists && target.isEnabled); hittable=\(exists && target.isHittable); frame=\(exists ? target.frame : .zero)")
        if exists { print("ACCOUNT_COLLECTION_TARGET_AX " + target.debugDescription) }
        print("ACCOUNT_COLLECTION_NAVIGATION_AX " + app.navigationBars.debugDescription)
    }
    private func assertChineseNavigation(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let destination = app.navigationBars[title]
        let arrived = destination.waitForExistence(timeout: 5)
        logNavigationBoundary("after destination wait: " + title, target: destination, identifier: title)
        XCTAssertTrue(arrived, file: file, line: line)
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
        app.segmentedControls["accountCollection.favorites.tabs"].buttons["Topics"].tap()
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
        app.segmentedControls["accountCollection.favorites.tabs"].buttons["Topics"].tap()
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
        app.segmentedControls["accountCollection.favorites.tabs"].buttons["Topics"].tap()
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
        open("accountCollection.openFavorites", diagnoseNavigation: true)
        assertChineseNavigation("我的收藏")
        XCTAssertTrue(app.segmentedControls["accountCollection.favorites.tabs"].buttons["动态"].exists)
        XCTAssertTrue(app.segmentedControls["accountCollection.favorites.tabs"].buttons["主题"].exists)
        app.navigationBars["我的收藏"].buttons.firstMatch.tap()
        open("accountCollection.openCoupons", diagnoseNavigation: true)
        assertChineseNavigation("我的优惠券")
        open("accountCollection.coupon.701", diagnoseNavigation: true)
        assertChineseNavigation("优惠券详情")
    }
    func testLargeTypeDarkModeKeepsCardsAndCouponDetailsReachable() {
        launch(extra: ["--uitesting-dark", "--uitesting-large-text"])
        assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility3")
        open("accountCollection.openFavorites")
        app.segmentedControls["accountCollection.favorites.tabs"].buttons["Topics"].tap()
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

    func testSavedPostsAreDefaultAndOpenLegacyDetailThenReturn() {
        launch(); open("accountCollection.openFavorites")
        let first = app.buttons["accountCollection.post.801"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["accountCollection.favorite.301"].exists)
        reveal(first); first.tap()
        XCTAssertTrue(app.navigationBars["Post details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["square.detailPost"].firstMatch.waitForExistence(timeout: 5))
        open("Close")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let tabs = app.segmentedControls["accountCollection.favorites.tabs"]
        tabs.buttons["Topics"].tap()
        XCTAssertTrue(app.buttons["accountCollection.favorite.301"].waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists)
        tabs.buttons["Posts"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
    }
    func testSavedPostPageFailureRetainsRowsAndRetryDoesNotSkip() {
        launch("postPageFailure"); open("accountCollection.openFavorites")
        let more = app.buttons["accountCollection.posts.loadMore"]
        reveal(more); more.tap()
        XCTAssertTrue(app.staticTexts["Sample saved post page unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accountCollection.post.801"].exists)
        let retry = app.buttons["accountCollection.retry"]
        reveal(retry); retry.tap()
        XCTAssertTrue(app.buttons["accountCollection.post.803"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "accountCollection.post.801").count, 1)
    }
    func testSavedPostFailureDoesNotPoisonTopicCollection() {
        launch("postFailure"); open("accountCollection.openFavorites")
        XCTAssertTrue(app.staticTexts["Sample saved posts unavailable"].waitForExistence(timeout: 5))
        app.segmentedControls["accountCollection.favorites.tabs"].buttons["Topics"].tap()
        XCTAssertTrue(app.buttons["accountCollection.favorite.301"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample saved posts unavailable"].exists)
    }
    func testSavedPostsDistinguishEmptyFromUnavailableAndClearOnSignOut() {
        launch("empty"); open("accountCollection.openFavorites")
        XCTAssertTrue(app.descendants(matching: .any)["accountCollection.posts.empty"].firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        launch("sessionChange"); open("accountCollection.openFavorites")
        XCTAssertTrue(app.buttons["accountCollection.post.801"].waitForExistence(timeout: 5))
        open("accountCollection.fixture.signOut")
        open("accountCollection.openFavorites")
        XCTAssertTrue(app.staticTexts["Sign in to see your saved collections"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["accountCollection.post.801"].exists)
    }

}
