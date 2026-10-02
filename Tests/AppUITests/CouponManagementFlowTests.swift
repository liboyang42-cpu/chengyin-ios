import XCTest

final class CouponManagementFlowTests: XCTestCase {
    private func launch(_ extras: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments += ["--ui-coupon-management", "-AppleLanguages", "(en)"] + extras; app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 { if element.isHittable { return }; app.swipeUp() }
    }
    func testPublishedDefinitionsAndSourceStopReview() {
        let app = launch()
        let row = app.buttons["couponManagement.definition.710"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let stop = app.buttons["couponManagement.stop.review"]; reveal(stop, app: app); stop.tap()
        let confirm = app.buttons["couponManagement.confirm"]; reveal(confirm, app: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 3)); XCTAssertTrue(confirm.isEnabled)
        // Merely reviewing sends nothing; fixture confirms are synthetic only.
    }
    func testProductionStyleGateHasDisabledConfirmation() {
        let app = launch(["--coupon-management-disabled"])
        app.buttons["couponManagement.create"].tap()
        let review = app.buttons["couponManagement.publish.review"]; reveal(review, app: app); review.tap()
        let confirm = app.buttons["couponManagement.confirm"]; reveal(confirm, app: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 3)); XCTAssertFalse(confirm.isEnabled)
    }
    func testBlankDraftHasExplainableDisabledReview() {
        let app = launch(["--coupon-management-blank"]); app.buttons["couponManagement.create"].tap()
        let review = app.buttons["couponManagement.publish.review"]; reveal(review, app: app)
        XCTAssertFalse(review.isEnabled); XCTAssertTrue(app.staticTexts["Enter a coupon name"].exists)
    }
    func testSignOutRemovesOwnedRows() {
        let app = launch(); XCTAssertTrue(app.buttons["couponManagement.definition.710"].waitForExistence(timeout: 5))
        app.buttons["couponManagement.fixture.signOut"].tap()
        XCTAssertFalse(app.buttons["couponManagement.definition.710"].exists)
    }
    func testStoppedDefinitionHasNoStopAction() {
        let app = launch(); let row = app.buttons["couponManagement.definition.711"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap(); app.swipeUp()
        XCTAssertFalse(app.buttons["couponManagement.stop.review"].exists)
    }
}
