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
    func testParticipantCreateRequiresConfirmationAndReadsBack() {
        launch(["--uitesting-module","participants"])
        XCTAssertTrue(app.staticTexts["module.fixture.notice"].waitForExistence(timeout:10))
        tap(app.buttons["participant.list.add"])
        let name=app.textFields["participant.form.name"]
        tap(name);name.typeText("Fixture Added Person")
        let phone=app.textFields["participant.form.phone"]
        tap(phone);phone.typeText("13800000001")
        tap(app.buttons["participant.form.save"])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["profile.participant.912"].exists)
        tap(app.alerts.buttons["Save participant"])
        XCTAssertTrue(app.buttons["profile.participant.912"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertTrue(app.buttons["profile.participant.912"].label.contains("Fixture Added Person"))
        capture("Participant create – synthetic memory-only store")
    }
    func testPlayChoiceSubmissionUsesOfflineReadback() {
        launch(["--uitesting-module","play","--uitesting-play-scenario","choice"])
        XCTAssertTrue(app.staticTexts["module.fixture.notice"].waitForExistence(timeout:10))
        let node=app.buttons["play.node.701"]
        XCTAssertTrue(node.waitForExistence(timeout:10))
        for _ in 0..<4 { if node.isHittable { break };app.swipeUp() }
        tap(node)
        let choice=app.buttons["play.option.A"]
        XCTAssertTrue(choice.waitForExistence(timeout:5))
        for _ in 0..<4 { if choice.isHittable { break };app.swipeUp() }
        tap(choice)
        let submit=app.buttons["play.answer.submit"]
        for _ in 0..<4 { if submit.isHittable { break };app.swipeUp() }
        tap(submit)
        XCTAssertTrue(app.descendants(matching:.any)["play.answer.receipt"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertFalse(app.buttons["play.answer.submit"].exists,"Server-confirmed node cannot be submitted twice")
        capture("Choice answer receipt – synthetic transport only")
    }
}
