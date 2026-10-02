import XCTest

final class PublisherLifecycleUITests: XCTestCase {
    func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--publisher-lifecycle-fixture"]; app.launch(); return app
    }
    func testPricingReviewStaysDormant() {
        let app = launch(); app.buttons["publisher.fixturePricing"].tap()
        app.buttons["publisher.preview"].tap()
        XCTAssertTrue(app.textFields["publisher.finalPrice"].waitForExistence(timeout: 3))
        app.buttons["publisher.reviewPrice"].tap(); app.buttons["publisher.confirmPrice"].tap()
        XCTAssertTrue(app.staticTexts["publisher.message"].label.contains("Not sent"))
    }
    func testPaidPlayersAppearBeforeRefundConfirmation() {
        let app = launch(); app.buttons["publisher.fixtureCancel"].tap()
        XCTAssertFalse(app.buttons["publisher.confirmRefund"].exists)
        let reason = app.textFields["publisher.cancelReason"]; reason.tap(); reason.typeText("Fixture weather")
        app.buttons["publisher.refundPreview"].tap()
        XCTAssertTrue(app.staticTexts["publisher.paidPlayers"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["publisher.paidPlayers"].label.contains("3"))
        XCTAssertTrue(app.buttons["publisher.confirmRefund"].exists)
    }
    func testCreatorFormShowsExactReviewAndDisabledDispatch() {
        let app = launch(); app.buttons["publisher.fixtureCreator"].tap()
        let name = app.textFields["creatorApplication.name"]; XCTAssertTrue(name.waitForExistence(timeout: 3)); name.tap(); name.typeText("Fixture Creator")
        app.buttons["creatorApplication.review"].tap(); app.buttons["creatorApplication.confirm"].tap()
        XCTAssertTrue(app.staticTexts["creatorApplication.message"].label.contains("Not sent"))
    }
}
