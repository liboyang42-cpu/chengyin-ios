import XCTest

final class MerchantMarketingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { break }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func waitForLabel(_ element: XCUIElement, _ value: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }
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
        let effects = app.switches["merchantMarketing.acknowledgeEffects"]
        XCTAssertTrue(effects.waitForExistence(timeout: 5))
        // The SwiftUI switch's accessibility frame includes its multiline label.
        // Touch its trailing native control, then verify the state before confirming.
        effects.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let acknowledged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: effects)
        XCTAssertEqual(XCTWaiter.wait(for: [acknowledged], timeout: 5), .completed, app.debugDescription)
        let confirm = app.buttons["merchantMarketing.confirmSettlement"]
        XCTAssertTrue(confirm.isEnabled); confirm.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: confirm)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, app.debugDescription)
        let error = app.staticTexts["merchantMarketing.error"]
        reveal(error, app: app, upwards: false)
        XCTAssertEqual(error.label, "The outcome is unconfirmed. Resubmission is locked; do not settle this round again.")
        XCTAssertFalse(app.staticTexts["merchantMarketing.winners"].exists)
        waitForLabel(app.staticTexts["merchantMarketing.fixtureSettlementCount"], "1")
        reveal(option, app: app); option.tap()
        reveal(error, app: app, upwards: false)
        XCTAssertEqual(error.label, "This round has a submission record. Further settlement is blocked.")
        XCTAssertFalse(confirm.exists)
        waitForLabel(app.staticTexts["merchantMarketing.fixtureSettlementCount"], "1")
    }
    func testSessionChangeClearsReview() {
        let app = launch("insight")
        XCTAssertTrue(app.staticTexts["merchantMarketing.synthetic"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Synthetic suggestion"], app: app)
        app.buttons["merchantMarketing.fixtureSignOut"].tap()
        XCTAssertFalse(app.staticTexts["Synthetic suggestion"].exists)
    }
    func testChineseDeadlineWarningAndReview() {
        let app = launch("predictions", language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["今天不给答案就作废"].waitForExistence(timeout: 5))
        app.buttons["merchantMarketing.option.A"].tap()
        XCTAssertTrue(app.switches["merchantMarketing.acknowledgeEffects"].exists)
    }

    func testNormalMerchantWorkbenchOpensDormantMarketingInBothLanguages() {
        for language in ["en", "zh-Hans"] {
            let app = XCUIApplication()
            app.launchArguments += ["--uitesting-merchant-fixture", "owner", "-AppleLanguages", "(\(language))",
                                    "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
            app.launch()
            let entry = app.buttons["merchantMarketing.entry"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
            XCTAssertTrue(app.staticTexts["merchantMarketing.error"].waitForExistence(timeout: 5))
            let picker = app.buttons["merchantMarketing.sectionPicker"]
            XCTAssertTrue(picker.exists)
            let sections = language == "en" ? ["Shop insights", "Entitlements", "Prediction inbox"] : ["店铺参谋", "付费权益", "竞猜待答"]
            for section in sections {
                picker.tap()
                let options = app.buttons.matching(identifier: section)
                guard options.firstMatch.waitForExistence(timeout: 5) else {
                    XCTFail("Expected marketing section option: \(section)"); return
                }
                options.element(boundBy: options.count - 1).tap()
                XCTAssertTrue(app.staticTexts["merchantMarketing.error"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["merchantMarketing.confirmSettlement"].exists)
            }
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.name = "Normal merchant dormant destination \(language)"; screen.lifetime = .keepAlways; add(screen)
            XCTAssertFalse(app.buttons["merchantMarketing.confirmSettlement"].exists)
            XCTAssertFalse(app.buttons["Purchase"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(entry.exists); app.terminate()
        }
    }
    func testInactiveMerchantDoesNotExposeMarketing() {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting-merchant-fixture", "inactive", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["merchant.access.inactive"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["merchantMarketing.entry"].exists)
    }
}
