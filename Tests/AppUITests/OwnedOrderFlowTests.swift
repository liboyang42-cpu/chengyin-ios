import XCTest

final class OwnedOrderFlowTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false}
    private func launch(_ options:[String]=[],language:String="en")->XCUIApplication{
        let app=XCUIApplication();app.launchArguments=["--uitesting-reset-language","--uitesting-module","ownedOrderHistory","-AppleLanguages","(\(language))","-AppleLocale",language]+options;app.launch();return app
    }
    private func openOrders(_ app:XCUIApplication){
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","signed-in"),object:app.staticTexts["orders.fixture.identity"])
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:8),.completed)
        let link=app.buttons["profile.open.orders"];XCTAssertTrue(revealFixtureElement(link,in:app));link.tap()
    }
    private func detail(_ app:XCUIApplication){let row=app.buttons["profile.order.41"];XCTAssertTrue(row.waitForExistence(timeout:5));row.tap()}
    private func cleared(_ element:XCUIElement){XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:element)],timeout:5),.completed)}
    func testNormalAccountFreshDetailBackAndExactUnroundedMoney(){
        let app=launch();openOrders(app);detail(app)
        XCTAssertTrue(app.staticTexts["Fresh owner detail"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["9007199254740993.0123456"].exists)
        XCTAssertFalse(app.buttons["profile.order.lifecycle"].exists)
        app.navigationBars.buttons.firstMatch.tap();detail(app)
        XCTAssertTrue(app.staticTexts["Fresh owner detail"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["orders.fixture.other"].label,"0")
    }
    func testIdleLoadedScreenClearsImmediatelyOnExplicitRevocationAndExpiry(){
        for action in ["revoke","expire"]{
            let app=launch();openOrders(app);detail(app)
            let privateTitle=app.staticTexts["Fresh owner detail"];XCTAssertTrue(privateTitle.waitForExistence(timeout:5))
            app.buttons["orders.fixture."+action].tap();cleared(privateTitle)
            XCTAssertFalse(app.staticTexts["9007199254740993.0123456"].exists)
            XCTAssertEqual(app.staticTexts["orders.fixture.identity"].label,"signed-in")
            XCTAssertEqual(app.staticTexts["orders.fixture.reads"].label,"2");app.terminate()
        }
    }
    func testGuestUnapprovedEmptyAndMixedOwnerStates(){
        let guest=launch(["--orders-guest"]);XCTAssertTrue(guest.descendants(matching:.any)["profile.orders.signIn"].firstMatch.waitForExistence(timeout:5));XCTAssertEqual(guest.staticTexts["orders.fixture.reads"].label,"0");guest.terminate()
        let closed=launch(["--orders-unapproved"]);openOrders(closed);XCTAssertTrue(closed.descendants(matching:.any)["profile.orders.unavailable"].firstMatch.waitForExistence(timeout:5));XCTAssertEqual(closed.staticTexts["orders.fixture.reads"].label,"0");closed.terminate()
        let empty=launch(["--orders-empty"],language:"zh-Hans");openOrders(empty);XCTAssertTrue(empty.staticTexts["profile.orders.empty"].waitForExistence(timeout:5));empty.terminate()
        let mixed=launch(["--orders-mixed-owner"]);openOrders(mixed);XCTAssertTrue(mixed.staticTexts["profile.orders.error"].waitForExistence(timeout:5));XCTAssertFalse(mixed.buttons["profile.order.41"].exists)
    }
    func testRetryThenFreshDetail(){
        let app=launch(["--orders-fail-once"]);openOrders(app);detail(app)
        let retry=app.buttons["profile.order.detail.retry"];XCTAssertTrue(retry.waitForExistence(timeout:5));retry.tap()
        XCTAssertTrue(app.staticTexts["Fresh owner detail"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["orders.fixture.other"].label,"0")
    }
    func testDismissedRetryLate401DoesNotExpireCurrentSession(){
        let app=launch(["--orders-pause-retry"]);openOrders(app);detail(app)
        let retry=app.buttons["profile.order.detail.retry"];XCTAssertTrue(retry.waitForExistence(timeout:5));retry.tap()
        let release=app.buttons["orders.fixture.release"];XCTAssertTrue(release.waitForExistence(timeout:5));app.navigationBars.buttons.firstMatch.tap();release.tap();detail(app)
        XCTAssertTrue(app.staticTexts["Fresh owner detail"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["orders.fixture.identity"].label,"signed-in")
    }
    func testCurrent401ClearsPrivateContent(){
        let app=launch(["--orders-current401"]);openOrders(app);detail(app)
        XCTAssertTrue(app.descendants(matching:.any)["profile.orders.signIn"].firstMatch.waitForExistence(timeout:5));XCTAssertFalse(app.staticTexts["Fresh owner detail"].exists)
    }
}
