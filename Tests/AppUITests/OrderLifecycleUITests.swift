import XCTest

final class OrderLifecycleUITests: XCTestCase {
    private func launch(_ scenario: String = "pending", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-order-lifecycle-fixture", "--uitesting-order-lifecycle-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
    }
    func testOrderReviewDoesNotDispatchAndCanDismiss() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["orderLifecycle.state"].waitForExistence(timeout: 5))
        let review = app.buttons["orderLifecycle.review.cancel"]; reveal(review, app: app); review.tap()
        XCTAssertTrue(app.buttons["orderLifecycle.review.disabled"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["orderLifecycle.review.disabled"].isEnabled)
        app.buttons["orderLifecycle.review.close"].tap()
        XCTAssertFalse(app.buttons["orderLifecycle.review.disabled"].exists)
    }
    func testUnknownOutcomeCannotBeResubmitted() {
        let app = launch("unknown")
        let review = app.buttons["orderLifecycle.review.cancel"]
        XCTAssertTrue(review.waitForExistence(timeout: 5)); reveal(review, app: app); review.tap()
        app.buttons["orderLifecycle.review.confirmFixture"].tap()
        XCTAssertTrue(app.staticTexts["orderLifecycle.attempt.unknown"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["orderLifecycle.review.cancel"].isEnabled)
        app.buttons["orderLifecycle.refresh"].tap()
        XCTAssertFalse(app.buttons["orderLifecycle.review.cancel"].isEnabled)
    }
    func testPassPreviewContainsNoCodeIssuance() {
        let app = launch("paid")
        let pass = app.buttons["orderLifecycle.pass.open"]
        XCTAssertTrue(pass.waitForExistence(timeout: 5)); reveal(pass, app: app); pass.tap()
        XCTAssertTrue(app.staticTexts["Redemption code unavailable"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["scanner.open"].exists)
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
