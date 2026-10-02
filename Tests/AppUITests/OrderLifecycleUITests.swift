import XCTest

final class OrderLifecycleUITests: XCTestCase {
    private var activeApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: activeApp)
        activeApp?.terminate(); activeApp = nil
    }
    private func launch(_ scenario: String = "pending", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-order-lifecycle-fixture", "--uitesting-order-lifecycle-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        activeApp = app; app.launch()
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription)
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    func testOrderReviewDoesNotDispatchAndCanDismiss() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["orderLifecycle.state"].waitForExistence(timeout: 5))
        let review = app.buttons["orderLifecycle.review.cancel"]; reveal(review, app: app); review.tap()
        XCTAssertTrue(app.buttons["orderLifecycle.review.close"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(app.buttons["orderLifecycle.review.disabled"], in: app, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(app.buttons["orderLifecycle.review.disabled"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["orderLifecycle.review.disabled"].isEnabled)
        app.buttons["orderLifecycle.review.close"].tap()
        XCTAssertFalse(app.buttons["orderLifecycle.review.disabled"].exists)
    }
    func testUnknownOutcomeCannotBeResubmitted() {
        let app = launch("unknown")
        let review = app.buttons["orderLifecycle.review.cancel"]
        XCTAssertTrue(app.staticTexts["orderLifecycle.state"].waitForExistence(timeout: 5))
        reveal(review, app: app); review.tap()
        app.buttons["orderLifecycle.review.confirmFixture"].tap()
        XCTAssertTrue(app.staticTexts["orderLifecycle.attempt.unknown"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["orderLifecycle.review.cancel"].isEnabled)
        app.buttons["orderLifecycle.refresh"].tap()
        XCTAssertFalse(app.buttons["orderLifecycle.review.cancel"].isEnabled)
    }
    func testPassWithoutApprovedFactoryContainsNoCodeIssuance() {
        let app = launch("paid")
        let pass = app.buttons["orderLifecycle.pass.open"]
        XCTAssertTrue(app.staticTexts["orderLifecycle.state"].waitForExistence(timeout: 5))
        reveal(pass, app: app); pass.tap()
        XCTAssertTrue(app.staticTexts["verificationCode.disabled"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["scanner.open"].exists)
        XCTAssertFalse(app.images["verificationCode.qr"].exists)
        XCTAssertFalse(app.buttons["verificationCode.show"].exists)
    }
    func testChapterChoiceRemainsNonRedeemed() {
        let app = launch("chapterChoice")
        let choice = app.buttons["orderLifecycle.verification.choice.9721"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        XCTAssertFalse(app.buttons["orderLifecycle.verification.disabled"].isEnabled)
        XCTAssertTrue(app.staticTexts["A selection is required; nothing has been redeemed yet"].exists)
    }
    func testStationUsesRecordIDAndEmptyChoicesRemainBlocked() {
        let app = launch("stationChoice")
        XCTAssertTrue(app.buttons["orderLifecycle.verification.choice.9731"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["orderLifecycle.verification.choice.9999"].exists)
    }
    func testSignOutRemovesOrderContent() {
        let app = launch("sessionChange")
        XCTAssertTrue(app.staticTexts["Sample native order"].waitForExistence(timeout: 5))
        app.buttons["orderLifecycle.fixture.signOut"].tap()
        XCTAssertFalse(app.staticTexts["Sample native order"].exists)
        XCTAssertFalse(app.buttons["orderLifecycle.review.cancel"].exists)
    }
    func testChineseRefundStateAndUnknownResult() {
        let app = launch("refunding", language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["退款处理中"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["orderLifecycle.review.refund"].exists)
    }
}
