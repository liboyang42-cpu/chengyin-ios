import XCTest

final class ModuleFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure=false;app=XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app); app.terminate();app=nil }
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
    func testClubMemberPublicProfileReturnsAndReopens() {
        launch(["--uitesting-club-fixture", "member"])
        tap(app.buttons["club.home.joined.81"])
        let members = app.buttons["club.openMembers"]
        if !members.isHittable { app.swipeUp() }
        tap(members)
        for memberID in [703, 704] {
            tap(app.buttons["club.member.\(memberID)"])
            XCTAssertTrue(app.staticTexts["Example city explorer"].waitForExistence(timeout: 5), app.debugDescription)
            tap(app.navigationBars.buttons.firstMatch)
            XCTAssertTrue(app.buttons["club.member.\(memberID)"].waitForExistence(timeout: 5), app.debugDescription)
        }
    }
    func testClubMemberProfileClearsOnSignOut() {
        launch(["--uitesting-club-fixture", "owner"])
        tap(app.buttons["club.home.owned.81"])
        let members = app.buttons["club.openMembers"]
        if !members.isHittable { app.swipeUp() }
        tap(members)
        tap(app.buttons["club.member.703"])
        XCTAssertTrue(app.staticTexts["Example city explorer"].waitForExistence(timeout: 5))
        tap(app.buttons["club.fixture.signOut"])
        XCTAssertTrue(app.buttons["club.home.signIn"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Example city explorer"].exists)
        XCTAssertFalse(app.buttons["club.member.703"].exists)
    }
    func testClubCustomerChoiceOwnerAndAdministrator() {
        for scenario in ["customerOwner", "customerAdministrator"] {
            launch(["--uitesting-club-fixture", scenario])
            tap(app.buttons["club.member.704"])
            tap(app.buttons["club.member.choice.public"])
            XCTAssertTrue(app.staticTexts["Example city explorer"].waitForExistence(timeout: 5))
            tap(app.navigationBars.buttons.firstMatch)
            tap(app.buttons["club.member.704"])
            tap(app.buttons["Cancel"])
            XCTAssertTrue(app.buttons["club.member.704"].exists)
            tap(app.buttons["club.member.704"])
            tap(app.buttons["club.member.choice.customer"])
            XCTAssertTrue(app.staticTexts["Fixture customer"].waitForExistence(timeout: 5), app.debugDescription)
            tap(app.navigationBars.buttons.firstMatch)
            XCTAssertTrue(app.buttons["club.member.704"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }
    func testClubCustomerChoiceDeniedAndWrongMemberFailClosed() {
        for (scenario, member) in [("customerDenied", 704), ("customerOwner", 703)] {
            launch(["--uitesting-club-fixture", scenario])
            tap(app.buttons["club.member.\(member)"])
            tap(app.buttons["club.member.choice.customer"])
            XCTAssertTrue(app.staticTexts["club.gov.error"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertFalse(app.staticTexts["Fixture customer"].exists)
            app.terminate()
        }
    }
    func testClubCustomerDetailClearsOnRoleRevisionThenRechecks() {
        launch(["--uitesting-club-fixture", "customerOwner"])
        tap(app.buttons["club.member.704"])
        tap(app.buttons["club.member.choice.customer"])
        XCTAssertTrue(app.staticTexts["Fixture customer"].waitForExistence(timeout: 5))
        tap(app.buttons["club.fixture.revokeRole"])
        XCTAssertTrue(app.buttons["club.member.704"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Fixture customer"].exists)
        tap(app.buttons["club.member.704"])
        tap(app.buttons["club.member.choice.customer"])
        XCTAssertTrue(app.staticTexts["club.gov.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Fixture customer"].exists)
    }
    func testClubCustomerRoleABADoesNotRestoreOldPrivateDestination() {
        launch(["--uitesting-club-fixture", "customerOwner"])
        tap(app.buttons["club.member.704"])
        tap(app.buttons["club.member.choice.customer"])
        XCTAssertTrue(app.staticTexts["Fixture customer"].waitForExistence(timeout: 5))
        tap(app.buttons["club.fixture.revokeRole"])
        tap(app.buttons["club.fixture.restoreRole"])
        XCTAssertTrue(app.buttons["club.member.704"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Fixture customer"].exists)
        tap(app.buttons["club.member.704"])
        tap(app.buttons["club.member.choice.customer"])
        XCTAssertTrue(app.staticTexts["Fixture customer"].waitForExistence(timeout: 5))
    }
    func testClubCustomerDetailClearsOnAccountSwitch() {
        launch(["--uitesting-club-fixture", "customerOwner"])
        tap(app.buttons["club.member.704"])
        tap(app.buttons["club.member.choice.customer"])
        XCTAssertTrue(app.staticTexts["Fixture customer"].waitForExistence(timeout: 5))
        tap(app.buttons["club.fixture.switchAccount"])
        XCTAssertTrue(app.staticTexts["club.members.error"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Fixture customer"].exists)
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
        XCTAssertTrue(app.navigationBars["Route task"].waitForExistence(timeout:5),app.debugDescription)
        let choice=app.buttons["play.option.A"]
        // Form lazily instantiates offscreen rows; reveal before querying existence.
        for _ in 0..<6 { if choice.exists && choice.isHittable { break };app.swipeUp() }
        XCTAssertTrue(choice.waitForExistence(timeout:5),app.debugDescription)
        tap(choice)
        let submit=app.buttons["play.answer.submit"]
        for _ in 0..<6 { if submit.exists && submit.isHittable { break };app.swipeUp() }
        tap(submit)
        let receipt=app.descendants(matching:.any)["play.answer.receipt"]
        for _ in 0..<4 { if receipt.exists { break };app.swipeUp() }
        XCTAssertTrue(receipt.waitForExistence(timeout:10),app.debugDescription)
        XCTAssertFalse(app.buttons["play.answer.submit"].exists,"Server-confirmed node cannot be submitted twice")
        XCTAssertTrue(revealFixtureElement(choice, in: app, towardTop: true), app.debugDescription)
        XCTAssertTrue(choice.isSelected, "The exact accepted A choice stays selected after authoritative readback")
        XCTAssertFalse(choice.isEnabled, "Accepted choice remains locked against duplicate submission")
        capture("Choice answer receipt – synthetic transport only")
    }
    func testTextComposerUsesSyntheticServerReceiptAndReadback() {
        launch(["--uitesting-module","composer"])
        XCTAssertTrue(app.staticTexts["module.fixture.notice"].waitForExistence(timeout:10))
        let input=app.descendants(matching:.any)["message.send.input"]
        tap(input);input.typeText("Fixture sent text")
        tap(app.buttons["message.send.button"])
        XCTAssertTrue(app.descendants(matching:.any)["message.send.receipt"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertTrue(app.buttons["messaging.message.2"].waitForExistence(timeout:10),app.debugDescription)
        XCTAssertTrue(app.buttons["messaging.message.2"].label.contains("Fixture sent text"))
        capture("Text message receipt – synthetic memory-only store")
    }
    func testRegistrationProductionPolicyCannotCreate() {
        launch(["--uitesting-registration-fixture","disabled"])
        XCTAssertTrue(app.navigationBars["Activity registration"].waitForExistence(timeout:10))
        let review=app.buttons["registration.form.review"]
        for _ in 0..<8 { if review.exists && review.isHittable { break };app.swipeUp() }
        XCTAssertTrue(review.exists,app.debugDescription)
        XCTAssertFalse(review.isEnabled)
        XCTAssertFalse(app.switches["registration.form.consent"].exists)
        capture("Registration creation gate – offline fixture")
    }
    func testRegistrationDemoReadbackDoesNotCreateAnotherIntent() {
        launch(["--uitesting-registration-fixture","standard"])
        XCTAssertTrue(app.navigationBars["Activity registration"].waitForExistence(timeout:10))
        let consent=app.switches["registration.form.consent"]
        for _ in 0..<8 { if consent.exists && consent.isHittable { break };app.swipeUp() }
        // iOS exposes both the full Toggle row and its UISwitch child. Tap the
        // actual switch: tapping the row's text activation point need not toggle it.
        let control=consent.switches.firstMatch
        tap(control.exists ? control : consent)
        let review=app.buttons["registration.form.review"]
        for _ in 0..<3 { if review.exists && review.isHittable { break };app.swipeUp() }
        XCTAssertEqual(consent.value as? String,"1",app.debugDescription)
        XCTAssertTrue(review.isEnabled,app.debugDescription)
        tap(review)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout:5),app.debugDescription)
        tap(app.alerts.buttons["Create demo registration"])
        let read=app.buttons["registration.form.readStatus"]
        XCTAssertTrue(read.waitForExistence(timeout:10),app.debugDescription)
        tap(read)
        let snapshot=app.descendants(matching:.any)["registration.form.statusSnapshot"].firstMatch
        for _ in 0..<5 { if snapshot.exists { break };app.swipeUp() }
        XCTAssertTrue(snapshot.waitForExistence(timeout:10),app.debugDescription)
        let paymentStatus=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Awaiting payment")).firstMatch
        // The section header can exist while its lower Form rows remain uninstantiated.
        // Reveal the actual status value, not just the header, before asserting readback.
        for _ in 0..<6 { if paymentStatus.exists { break };app.swipeUp() }
        XCTAssertTrue(paymentStatus.waitForExistence(timeout:10),app.debugDescription)
        XCTAssertFalse(app.buttons["registration.form.review"].exists)
        capture("Registration raw status – synthetic data")
        tap(app.buttons["registration.form.close"])
        tap(app.buttons["registration.fixture.open"])
        XCTAssertTrue(app.buttons["registration.form.readStatus"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["registration.form.review"].exists,"Reopening must retain the original intent")
    }
}
