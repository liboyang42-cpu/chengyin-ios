import XCTest

@MainActor final class ProfileOrderFilterFlowTests: XCTestCase {
    private var app:XCUIApplication!
    override func setUp() { continueAfterFailure=false; app=XCUIApplication() }
    private func launch(empty:Bool=false) {
        app.launchArguments=["--uitesting-reset-language","--uitesting-profile-order-filters","-AppleLanguages","(en)","-AppleLocale","en_US"] + (empty ? ["--profile-order-filters-empty"] : [])
        app.launch()
    }
    private func choose(_ text:String) {
        let picker=app.buttons["profile.orderFilter.picker"]; XCTAssertTrue(picker.waitForExistence(timeout:5));picker.tap()
        let option=app.buttons[text];XCTAssertTrue(option.waitForExistence(timeout:3));option.tap()
    }
    func testFilterAndClearDoNotReload() {
        launch();choose("Manual after-sales")
        XCTAssertTrue(app.staticTexts["profile.orderFilter.empty"].waitForExistence(timeout:3))
        let before=app.staticTexts["profile.orderFilter.fixture.listReads"].label
        app.buttons["profile.orderFilter.clear"].tap()
        XCTAssertTrue(app.buttons["profile.order.701"].exists)
        XCTAssertEqual(app.staticTexts["profile.orderFilter.fixture.listReads"].label,before)
    }
    func testRefunderRowOpensItsOriginalDetail() {
        launch();choose("Refunded");app.buttons["profile.order.705"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic refunded"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["profile.orderFilter.fixture.detailReads"].label,"1")
    }
    func testTrueEmptyIsNotFilteredEmpty() {
        launch(empty:true);XCTAssertTrue(app.staticTexts["profile.orders.empty"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["profile.orderFilter.empty"].exists)
    }
    func testRevocationHidesLoadedList() {
        launch();XCTAssertTrue(app.buttons["profile.order.701"].waitForExistence(timeout:5))
        app.buttons["profile.orderFilter.fixture.revoke"].tap()
        XCTAssertTrue(app.otherElements["profile.orders.unavailable"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["profile.orderFilter.picker"].exists)
    }
    func testAccountSwitchRemovesPreviousRows() {
        launch();choose("Refunded");app.buttons["profile.orderFilter.fixture.switch"].tap()
        XCTAssertTrue(app.staticTexts["profile.orders.empty"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["profile.order.705"].exists)
    }
}
