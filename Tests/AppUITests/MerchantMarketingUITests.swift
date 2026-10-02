import XCTest

final class MerchantMarketingUITests: XCTestCase {
    private func launch(_ surface: String, scenario: String = "normal", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--merchant-marketing-fixture", surface, "--merchant-marketing-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    func testDashboardSyntheticAndNoFalseZeroRate() {
        let app = launch("dashboard")
        XCTAssertTrue(app.staticTexts["merchantMarketing.synthetic"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Claimed"].exists)
        XCTAssertFalse(app.staticTexts["Redemption rate"].exists)
    }
    func testSubscriptionsPermanentAndNoCheckoutButton() {
        let app = launch("subscriptions")
        XCTAssertTrue(app.staticTexts["Permanent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["merchantMarketing.checkoutUnavailable"].exists)
        XCTAssertFalse(app.buttons["Purchase"].exists)
    }
    func testEmptySubscriptionsAreNotError() {
        let app = launch("subscriptions", scenario: "empty")
        XCTAssertTrue(app.staticTexts["merchantMarketing.emptyEntitlements"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["merchantMarketing.error"].exists)
    }
    func testPredictionReviewRequiresAcknowledgementAndCancelIsSafe() {
        let app = launch("predictions")
        let option = app.buttons["merchantMarketing.option.A"]
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        let confirm = app.buttons["merchantMarketing.confirmSettlement"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(confirm.isEnabled)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(confirm.exists); XCTAssertTrue(option.exists)
    }
    func testUnknownRetainsRoundAndLocksNewAttempt() {
        let app = launch("predictions", scenario: "unknown")
        let option = app.buttons["merchantMarketing.option.A"]
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        app.switches["merchantMarketing.acknowledgeEffects"].tap()
        app.buttons["merchantMarketing.confirmSettlement"].tap()
        XCTAssertTrue(app.staticTexts["merchantMarketing.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(option.exists); XCTAssertFalse(app.staticTexts["merchantMarketing.winners"].exists)
        option.tap(); XCTAssertFalse(app.buttons["merchantMarketing.confirmSettlement"].exists)
    }
    func testSessionChangeClearsReview() {
        let app = launch("insight")
        XCTAssertTrue(app.staticTexts["Synthetic suggestion"].waitForExistence(timeout: 5))
        app.buttons["merchantMarketing.fixtureSignOut"].tap()
        XCTAssertFalse(app.staticTexts["Synthetic suggestion"].exists)
    }
    func testChineseDeadlineWarningAndReview() {
        let app = launch("predictions", language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["今天不给答案就作废"].waitForExistence(timeout: 5))
        app.buttons["merchantMarketing.option.A"].tap()
        XCTAssertTrue(app.switches["merchantMarketing.acknowledgeEffects"].exists)
    }
}
