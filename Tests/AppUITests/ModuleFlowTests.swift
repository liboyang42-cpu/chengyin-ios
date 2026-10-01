import XCTest

final class ModuleFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure=false;app=XCUIApplication() }
    override func tearDownWithError() throws { app.terminate();app=nil }
    private func launch(_ arguments:[String]) {
        app.launchArguments=["--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"]+arguments
        app.launch()
    }
    private func tap(_ element:XCUIElement,file:StaticString=#filePath,line:UInt=#line) {
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND hittable == true"),object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed,app.debugDescription,file:file,line:line)
        element.tap()
    }
    private func capture(_ name:String) {
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    func testDiscoveryTemplateNavigationAndBack() {
        launch(["--uitesting-module","discovery"])
        XCTAssertTrue(app.staticTexts["module.fixture.notice"].waitForExistence(timeout:10))
        tap(app.buttons["discovery.openTemplates"])
        XCTAssertTrue(app.navigationBars["Browse templates"].waitForExistence(timeout:5))
        capture("Discovery template shelf – synthetic data")
        tap(app.navigationBars.buttons.firstMatch)
        XCTAssertTrue(app.buttons["discovery.openTemplates"].waitForExistence(timeout:5))
    }
    func testProfileOrderReadbackAndBack() {
        launch(["--uitesting-module","profile"])
        XCTAssertTrue(app.staticTexts["module.fixture.notice"].waitForExistence(timeout:10))
        tap(app.buttons["profile.open.orders"])
        tap(app.buttons["profile.order.901"])
        XCTAssertTrue(app.navigationBars["Order details"].waitForExistence(timeout:5))
        let reference=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "FIXTURE-901")).firstMatch
        XCTAssertTrue(reference.waitForExistence(timeout:5),app.debugDescription)
        capture("Order detail – synthetic data")
        tap(app.navigationBars["Order details"].buttons.firstMatch)
        XCTAssertTrue(app.buttons["profile.order.901"].waitForExistence(timeout:5))
    }
    func testMerchantFinanceRoleDoesNotExposeOwnerDashboard() {
        launch(["--uitesting-merchant-fixture","finance"])
        XCTAssertTrue(app.staticTexts["merchant.fixture.notice"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["merchant.orders.entry"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["merchant.projects.entry"].exists)
        XCTAssertFalse(app.descendants(matching:.any)["merchant.dashboard.revenue"].exists)
        tap(app.buttons["merchant.orders.entry"])
        XCTAssertTrue(app.buttons["merchant.order.row.101"].waitForExistence(timeout:10))
        capture("Merchant finance orders – synthetic data")
    }
    func testClubMemberGateAndReadOnlyMemberList() {
        launch(["--uitesting-club-fixture","owner"])
        XCTAssertTrue(app.staticTexts["club.fixture.notice"].waitForExistence(timeout:10))
        tap(app.buttons["club.home.owned.81"])
        XCTAssertTrue(app.navigationBars["Club details"].waitForExistence(timeout:5))
        let members=app.buttons["club.openMembers"]
        if !members.isHittable { app.swipeUp() }
        tap(members)
        XCTAssertTrue(app.descendants(matching:.any)["club.member.701"].waitForExistence(timeout:5),app.debugDescription)
        capture("Club members – synthetic data")
    }
    func testMessagingReadOnlyHistoryNavigation() {
        launch(["--uitesting-module","messaging"])
        XCTAssertTrue(app.staticTexts["module.fixture.notice"].waitForExistence(timeout:10))
        tap(app.buttons["messaging.conversation.901"])
        XCTAssertTrue(app.navigationBars["Conversation"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["messaging.history.earlier"].waitForExistence(timeout:5))
        XCTAssertFalse(app.textViews.firstMatch.exists,"Read-only history exposes no message composer")
        capture("Conversation – synthetic data")
        tap(app.navigationBars["Conversation"].buttons.firstMatch)
        XCTAssertTrue(app.buttons["messaging.conversation.901"].waitForExistence(timeout:5))
    }
    func testRoamSyntheticListOpensDetail() {
        launch(["--uitesting-module","roam"])
        XCTAssertTrue(app.staticTexts["module.fixture.notice"].waitForExistence(timeout:10))
        tap(app.buttons["roam.display.toggle"])
        tap(app.buttons["roam.row.place-901"])
        XCTAssertTrue(app.navigationBars["Map details"].waitForExistence(timeout:5))
        capture("Map detail – synthetic data")
    }
}
