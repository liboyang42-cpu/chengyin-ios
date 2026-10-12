import XCTest

final class ProfileSelfOrdersFlowTests:XCTestCase {
    private var app:XCUIApplication!
    override func setUpWithError() throws {continueAfterFailure=false;app=XCUIApplication()}
    override func tearDownWithError() throws {app.terminate();app=nil}
    private func launch(_ scenario:String="content") {
        app.launchArguments=["--uitesting-profile-self-orders","--profile-self-orders-scenario",scenario,"--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
    }
    private func tap(_ element:XCUIElement) {
        for _ in 0..<5 {if element.exists && element.isHittable {break};app.swipeUp()}
        XCTAssertTrue(element.isHittable);element.tap()
    }
    func testCardOpensFreshExactOrderDetail() {
        launch();let row=app.buttons["profile.selfOrders.order.3"];XCTAssertTrue(row.waitForExistence(timeout:5));tap(row)
        XCTAssertTrue(app.staticTexts["SYNTHETIC-3"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["profile.selfOrdersFixture.detailReads"].label,"1")
    }
    func testInitialFailureRetriesWithoutFalseEmpty() {
        launch("failure");let retry=app.buttons["profile.selfOrders.retry"];XCTAssertTrue(retry.waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["profile.selfOrders.empty"].exists)
        tap(retry);XCTAssertTrue(app.buttons["profile.selfOrders.order.1"].waitForExistence(timeout:5))
    }
    func testRefreshFailureKeepsDisabledRowsAndRecovers() {
        launch("refreshFailure");XCTAssertTrue(app.buttons["profile.selfOrders.order.1"].waitForExistence(timeout:5));tap(app.buttons["profile.selfOrders.refresh"])
        XCTAssertTrue(app.staticTexts["profile.selfOrders.issue"].waitForExistence(timeout:5));app.swipeDown();XCTAssertFalse(app.buttons["profile.selfOrders.order.1"].isEnabled)
        tap(app.buttons["profile.selfOrders.retry"]);XCTAssertTrue(app.buttons["profile.selfOrders.order.1"].isEnabled)
    }
    func testSuccessfulEmptyHasItsOwnState() {launch("empty");XCTAssertTrue(app.staticTexts["profile.selfOrders.empty"].waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["profile.selfOrders.issue"].exists)}
    func testAllOrdersUsesExistingList() {
        launch();XCTAssertTrue(app.buttons["profile.selfOrders.order.1"].waitForExistence(timeout:5));tap(app.buttons["profile.selfOrders.all"])
        XCTAssertTrue(app.buttons["profile.order.1"].waitForExistence(timeout:5));tap(app.buttons["profile.order.10"]);XCTAssertTrue(app.staticTexts["SYNTHETIC-10"].waitForExistence(timeout:5))
    }
    func testOtherGuestAndUnapprovedDoNotRead() {
        for scenario in ["other","guest","unapproved"] {launch(scenario);XCTAssertTrue(app.staticTexts["profile.selfOrdersFixture.listReads"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["profile.selfOrdersFixture.listReads"].label,"0");XCTAssertFalse(app.buttons["profile.selfOrders.all"].exists);app.terminate()}
    }
    func testRevocationHidesPreview() {
        launch();XCTAssertTrue(app.buttons["profile.selfOrders.order.1"].waitForExistence(timeout:5));tap(app.buttons["profile.selfOrdersFixture.revoke"])
        XCTAssertFalse(app.buttons["profile.selfOrders.order.1"].exists)
    }
}
