import XCTest

final class RegistrationWaitlistUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String, language: String = "en", dark: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-registration-fixture", scenario]
        if dark { app.launchArguments += ["--uitesting-dark"] }
        else { app.launchArguments += ["-AppleInterfaceStyle", "Light"] }
        app.launch()
        XCTAssertTrue(app.navigationBars[language == "en" ? "Activity registration" : "活动报名"].waitForExistence(timeout: 10))
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testClosedRegistrationSessionShowsReasonAndCannotReviewInBothLanguages() {
        for language in ["en", "zh-Hans"] {
            launch("signupClosed", language: language)
            let reason = app.staticTexts["registration.form.signupClosed"]; reveal(reason)
            XCTAssertEqual(reason.label, language == "en" ? "Registration for this session has closed. Choose another ticket or session." : "本场报名已截止，请选择其他票种或场次。")
            let review = app.buttons["registration.form.review"]; reveal(review)
            XCTAssertFalse(review.isEnabled)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            app.terminate()
        }
    }
    func testWaitingAndLeavingRemainInTheRegistrationForm() {
        launch("waitlistWaiting")
        let join = app.buttons["registration.waitlist.join"]; reveal(join); join.tap()
        let cancel = app.buttons["registration.waitlist.cancel"]; reveal(cancel)
        XCTAssertTrue(app.staticTexts["Waiting for an available place"].exists, app.debugDescription)
        capture("Waitlist waiting in native registration form – synthetic")
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Waitlist entry cancelled"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["registration.form.readStatus"].exists)
        XCTAssertTrue(app.navigationBars["Activity registration"].exists)
    }
    func testOfferRequiresNewConsentAndCancelledReviewDoesNotCreate() {
        launch("waitlistOffer")
        let offer = app.buttons["registration.waitlist.reviewOffer"]; reveal(offer); offer.tap()
        let consent = app.switches["registration.form.consent"]; reveal(consent)
        XCTAssertEqual(consent.value as? String, "0", app.debugDescription)
        let control = consent.switches.firstMatch; (control.exists ? control : consent).tap()
        let review = app.buttons["registration.form.review"]; reveal(review)
        XCTAssertTrue(review.isEnabled); review.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["registration.form.readStatus"].exists)
        capture("Waitlist offer review cancelled – synthetic")
        app.buttons["registration.form.close"].tap()
        app.buttons["registration.fixture.open"].tap()
        XCTAssertTrue(app.navigationBars["Activity registration"].waitForExistence(timeout: 5))
        reveal(app.buttons["registration.waitlist.reviewOffer"])
        XCTAssertFalse(app.buttons["registration.form.readStatus"].exists)
    }
    func testSoldOutGuidanceMatchesCapabilityAndStateInBothLanguages() {
        for language in ["en", "zh-Hans"] {
            for scenario in ["soldOut", "waitlistWaiting", "waitlistOffer"] {
                launch(scenario, language: language)
                if scenario == "waitlistWaiting" {
                    let join = app.buttons["registration.waitlist.join"]; reveal(join); join.tap()
                    XCTAssertTrue(app.buttons["registration.waitlist.cancel"].waitForExistence(timeout: 5))
                } else if scenario == "waitlistOffer" {
                    reveal(app.buttons["registration.waitlist.reviewOffer"])
                }
                let guidance = app.staticTexts["registration.form.soldOutGuidance"]
                XCTAssertTrue(revealFixtureElement(guidance, in: app, towardTop: scenario != "soldOut"), app.debugDescription)
                let expected: String
                switch (language, scenario) {
                case ("en", "soldOut"): expected = "This ticket is full. Waitlist service is unavailable in this form, so an offer cannot be reviewed here."
                case ("en", "waitlistWaiting"): expected = "You are on the waitlist. No place has been offered yet. Refresh the status below to check for an offer."
                case ("en", _): expected = "A waitlist place has been offered. Review the offer below for a fresh quote, then confirm contact sharing and registration. No payment is automatic."
                case (_, "soldOut"): expected = "此票种已满。此表单的候补服务不可用，暂时无法在此核对候补名额。"
                case (_, "waitlistWaiting"): expected = "你已加入候补，尚未获得名额。可在下方刷新状态，查看是否收到候补名额。"
                default: expected = "你已获得候补名额。请在下方核对名额并获取新报价，再确认联系信息共享和报名，不会自动付款。"
                }
                XCTAssertEqual(guidance.label, expected)
                capture("Waitlist capability guidance \(scenario) \(language) – synthetic")
                app.terminate()
            }
        }
    }
    func testEssentialQuoteAmountCaptureInLightAndDarkBothLanguages() {
        for language in ["en", "zh-Hans"] {
            for dark in [false, true] {
                launch("waitlistOffer", language: language, dark: dark)
                let amount = app.staticTexts["registration.form.memberDiscount.amount"]
                reveal(amount)
                XCTAssertTrue(amount.label.contains("CNY"), app.debugDescription)
                XCTAssertTrue(amount.label.contains("0.00"), app.debugDescription)
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", language == "en" ? "Currency unconfirmed" : "币种待确认")).firstMatch.exists)
                capture("Essential quote amounts \(language) \(dark ? "dark" : "light") – synthetic")
                app.terminate()
            }
        }
    }

    func testUnreviewedOfferGuidanceExpiresWhileFormRemainsOpen() {
        launch("waitlistExpiringOffer")
        let guidance = app.staticTexts["registration.form.soldOutGuidance"]
        XCTAssertTrue(revealFixtureElement(guidance, in: app), app.debugDescription)
        let offered = "A waitlist place has been offered. Review the offer below for a fresh quote, then confirm contact sharing and registration. No payment is automatic."
        let offeredExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", offered), object: guidance)
        XCTAssertEqual(XCTWaiter.wait(for: [offeredExpectation], timeout: 5), .completed)
        let arm = app.buttons["registration.fixture.armExpiry"]
        XCTAssertTrue(arm.exists && arm.isHittable, app.debugDescription)
        arm.tap()
        let expired = "This ticket is full. Check the waitlist status below. Registration requires a valid offer, a fresh quote and your confirmation."
        let expiredExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expired), object: guidance)
        XCTAssertEqual(XCTWaiter.wait(for: [expiredExpectation], timeout: 25), .completed)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("Unreviewed offer guidance after expiry – synthetic")
    }

}
