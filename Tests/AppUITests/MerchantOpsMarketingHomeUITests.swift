import XCTest

/// Offline marketing-home parity (source pages/merchant/marketing/index.wxml) through the DEBUG fixture host.
final class MerchantOpsMarketingHomeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ scenario: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting-reset-language", "--merchant-marketing-fixture", "dashboard", "--merchant-marketing-scenario", scenario,
                                "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func reveal(_ item: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<10 where !(item.exists && item.isHittable) { app.swipeUp() }
    }
    func testHeroShowsCompactSignupsWithoutFunnelRates() {
        let app = launch("normal")
        XCTAssertTrue(element("merchantOps.marketing.hero", app).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["1.2万"].exists || element("merchantOps.marketing.hero", app).label.contains("1.2万"))
        XCTAssertFalse(app.staticTexts["Redemption rate"].exists)
        XCTAssertFalse(element("merchantOps.marketing.coupon.rate", app).exists)
        let coop = element("merchantOps.marketing.coop", app); reveal(coop, app)
        XCTAssertTrue(coop.exists)
        XCTAssertFalse(element("merchantOps.marketing.empty", app).exists)
    }
    func testOwnerToolsFollowPermissions() {
        let app = launch("normal")
        XCTAssertTrue(element("merchantOps.marketing.tool.insight", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("merchantOps.marketing.tool.decor", app).exists)
        XCTAssertTrue(element("merchantOps.marketing.tool.topic", app).exists)
    }
    func testAllZeroShowsEmptyStateWithFirstContentAction() {
        let app = launch("marketing-empty", language: "zh-Hans")
        XCTAssertTrue(element("merchantOps.marketing.empty", app).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("merchantOps.marketing.firstContent", app).exists)
        let empty = element("merchantOps.marketing.coupon.empty", app); reveal(empty, app)
        XCTAssertTrue(empty.exists)
    }
    func testInvalidAnalyticsKeepsCountsAndOffersRetry() {
        let app = launch("marketing-bad-analytics")
        XCTAssertTrue(element("merchantOps.marketing.analytics.retry", app).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("merchantOps.marketing.couponDeck", app).exists || app.staticTexts["Claimed"].exists)
    }
    func testDeniedRoleShowsSourceCopyAndRecheck() {
        let app = launch("denied")
        XCTAssertTrue(element("merchantOps.marketing.denied", app).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("merchantOps.marketing.denied.retry", app).exists)
        XCTAssertFalse(element("merchantOps.marketing.hero", app).exists)
    }
}
