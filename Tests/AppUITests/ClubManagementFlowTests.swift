import XCTest

/// Synthetic DEBUG fixture only. Host must route --uitesting-club-management-fixture.
final class ClubManagementFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: app)
        if (testRun?.totalFailureCount ?? 0) > 0 {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Club management failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        app.terminate(); app = nil
    }
    private func launch(_ scenario: String) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-club-management-fixture", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["Offline synthetic club management fixture"].waitForExistence(timeout: 10))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func count(_ value: Int) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", String(value)), object: app.staticTexts["club.management.writes"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed, app.debugDescription)
    }
    private func open(_ type: String, _ id: Int) {
        let row = app.buttons["club.management.\(type).\(id)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(row, in: app, maximumSwipes: 5), app.debugDescription)
        XCTAssertTrue(row.isEnabled, app.debugDescription)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    func testApplicationDetailShowsServerMessageBeforeReview() {
        launch("owner")
        open("request", 703)
        let message = app.staticTexts["club.management.joinMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(message.label, "Night walks please 👋")
        count(0)
    }
    private func prepare(_ action: String, target: Int) -> XCUIElement {
        let button = app.buttons["club.management.\(action).\(target)"].firstMatch
        let detail = app.navigationBars[action == "remove" ? "Member details" : "Application details"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(detail.exists, app.debugDescription)
        XCTAssertTrue(button.isEnabled, app.debugDescription)
        XCTAssertTrue(revealFixtureElement(button, in: app, maximumSwipes: 5), app.debugDescription)
        guard let snapshot = try? button.snapshot(), snapshot.isEnabled,
              !snapshot.frame.isEmpty, app.frame.insetBy(dx: 4, dy: 4).contains(snapshot.frame),
              snapshot.frame.minY >= detail.frame.maxY, button.isHittable,
              button.descendants(matching: .button).count == 0,
              let readsBefore = Int(app.staticTexts["club.management.reads"].label) else {
            XCTFail("Expected an enabled visible detail action leaf and fixture read counter: " + app.debugDescription)
            return app
        }
        // The run97 AX activation tap left the enabled row untouched (reads stayed 1).
        // Tap its verified content frame once; require fresh read and review below.
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let sheet = app! // SwiftUI modal can expose Other rather than XCUIElementTypeSheet.
        let title = action == "approve" ? "Approve application" : action == "reject" ? "Reject application" : "Remove member"
        XCTAssertTrue(sheet.navigationBars[title].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["club.management.reads"].label, String(readsBefore + 1), "Preparing review must perform one new authoritative fixture read")
        XCTAssertTrue(sheet.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Fixture club (#81)")).firstMatch.exists,app.debugDescription)
        let name = target == 703 ? "Fixture applicant" : "Fixture member"
        XCTAssertTrue(sheet.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","\(name) (#\(target))")).firstMatch.exists,app.debugDescription)
        count(0)
        return sheet
    }
    private func submit(_ sheet: XCUIElement) {
        let matches = sheet.buttons.matching(identifier: "club.management.confirm")
        let bar = sheet.navigationBars.matching(NSPredicate(format: "identifier IN %@",
            ["Approve application", "Reject application", "Remove member"])).firstMatch
        func visibleActions() -> [XCUIElement] {
            guard bar.exists else { return [] }
            let bounds = app.frame.insetBy(dx: 4, dy: 4)
            let contentTop = bar.frame.maxY
            return matches.allElementsBoundByIndex.filter { button in
                let frame = button.frame
                return !frame.isEmpty && bounds.contains(frame) && frame.minY >= contentTop
                    && button.descendants(matching: .button).count == 0
                    && button.label == bar.identifier && button.isEnabled
            }
        }
        // Wait for materialization before requesting geometry/descendant snapshots.
        // Repeating all those AX requests inside a timed predicate can exhaust its
        // deadline even when the confirmation is already visible and enabled.
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        let actions = visibleActions()
        XCTAssertEqual(actions.count, 1, app.debugDescription)
        guard actions.count == 1, let leaf = actions.first else { XCTFail("Expected one visible confirmation action"); return }
        // The native sheet's AX activation point can be invalid despite a visible row.
        // Use its verified leaf frame; the caller still requires exactly one write.
        leaf.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    private func cancelReview(_ title: String) throws {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), app.debugDescription)
        let actions = bar.buttons.matching(NSPredicate(format: "label == %@", "Cancel"))
            .allElementsBoundByIndex.filter { $0.descendants(matching: .button).count == 0 }
        XCTAssertEqual(actions.count, 1, app.debugDescription)
        let cancel = try XCTUnwrap(actions.first)
        let snapshot = try cancel.snapshot()
        let bounds = app.frame.insetBy(dx: 4, dy: 4)
        XCTAssertTrue(snapshot.isEnabled && !snapshot.frame.isEmpty && bounds.contains(snapshot.frame), app.debugDescription)
        XCTAssertTrue(bar.frame.contains(snapshot.frame), app.debugDescription)
        // One tap in the actual Cancel leaf. Do not proceed to a host control
        // until the sheet is absent; run80 tried that control behind the sheet.
        cancel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: bar)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(app.buttons["club.management.confirm"].exists, app.debugDescription)
        XCTAssertTrue(app.navigationBars["Application details"].waitForExistence(timeout: 5), app.debugDescription)
        count(0)
    }
    func testApproveRequiresTargetConfirmation() {
        launch("owner"); open("request", 703)
        submit(prepare("approve", target: 703)); count(1)
    }
    func testRejectCancelSendsNothing() throws {
        launch("admin"); open("request", 703)
        _ = prepare("reject", target: 703)
        try cancelReview("Reject application")
    }
    func testCreatorRemovalRequiresTargetConfirmation() {
        launch("owner"); open("member", 704)
        submit(prepare("remove", target: 704)); count(1)
    }
    func testAdminHasApplicationsButNoRemovalDirectory() {
        launch("admin")
        XCTAssertTrue(element("club.management.request.703").waitForExistence(timeout: 5))
        XCTAssertFalse(element("club.management.member.704").exists); count(0)
    }
    func testCreatorRowHasNoRemoveAction() {
        launch("owner"); open("member", 701)
        XCTAssertFalse(app.buttons["club.management.remove.701"].exists); count(0)
    }
    func testAcknowledgedApplicationReturnsToFreshList() {
        launch("owner"); open("request", 703)
        submit(prepare("approve", target: 703)); count(1)
        XCTAssertTrue(app.navigationBars["Club management"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["club.management.request.703"].exists, app.debugDescription)
        XCTAssertFalse(app.navigationBars["Application details"].exists, app.debugDescription)
        XCTAssertEqual(app.staticTexts["club.management.changes"].label, "1")
        app.buttons["club.management.refresh"].tap()
        XCTAssertFalse(app.buttons["club.management.request.703"].exists)
        count(1)
    }
    func testAcknowledgedRemovalReturnsToFreshList() {
        launch("owner"); open("member", 704)
        submit(prepare("remove", target: 704)); count(1)
        XCTAssertTrue(app.navigationBars["Club management"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["club.management.member.704"].exists)
        XCTAssertTrue(app.buttons["club.management.member.701"].exists)
        XCTAssertEqual(app.staticTexts["club.management.changes"].label, "1")
    }
    func testUnknownOutcomeStaysVisibleAndRefreshNeverReplays() {
        launch("unknown"); open("request", 703)
        submit(prepare("approve", target: 703)); count(1)
        XCTAssertTrue(app.staticTexts["club.management.unknown"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Application details"].exists)
        XCTAssertEqual(app.staticTexts["club.management.changes"].label, "0")
        app.buttons["club.management.detail.refresh"].tap()
        XCTAssertTrue(app.staticTexts["club.management.unknown"].exists)
        XCTAssertFalse(app.buttons["club.management.approve.703"].exists)
        count(1)
    }
    func testAcknowledgementWithUnavailableReadbackIsExplicit() {
        launch("readbackUnavailable"); open("request", 703)
        submit(prepare("approve", target: 703)); count(1)
        XCTAssertTrue(app.navigationBars["Club management"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["club.management.readbackUnavailable"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["club.management.request.703"].exists)
        XCTAssertEqual(app.staticTexts["club.management.changes"].label, "1")
    }

    func testInterruptedUnknownRefreshDoesNotDisableListRefresh() {
        launch("unknownDelayedRefresh"); open("request", 703)
        submit(prepare("approve", target: 703)); count(1)
        XCTAssertTrue(app.staticTexts["club.management.unknown"].waitForExistence(timeout: 10))
        app.buttons["club.management.detail.refresh"].tap()
        XCTAssertTrue(element("club.management.detail.loading").waitForExistence(timeout: 2))
        app.navigationBars["Application details"].buttons.firstMatch.tap()
        let refresh = app.buttons["club.management.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(refresh.isEnabled, app.debugDescription)
        XCTAssertTrue(app.staticTexts["club.management.unknown"].exists)
        count(1)
    }
    func testActualClubDetailReloadsOnlyAfterReturningFromManagement() {
        launch("detailReturn")
        XCTAssertTrue(app.staticTexts["club.detail.name"].waitForExistence(timeout: 5))
        app.buttons["club.openManagement"].tap()
        open("request", 703); submit(prepare("approve", target: 703)); count(1)
        XCTAssertTrue(app.navigationBars["Club management"].waitForExistence(timeout: 10))
        app.navigationBars["Club management"].buttons.firstMatch.tap()
        let name = app.staticTexts["club.detail.name"]
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Fixture club refreshed"), object: name)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 10), .completed, app.debugDescription)
        count(1)
    }
    func testFailedParentReloadDoesNotDismissManagementReceipt() {
        launch("detailReturnUnavailable")
        XCTAssertTrue(app.staticTexts["club.detail.name"].waitForExistence(timeout: 5))
        app.buttons["club.openManagement"].tap()
        open("request", 703); submit(prepare("approve", target: 703)); count(1)
        XCTAssertTrue(app.navigationBars["Club management"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["club.detail.error"].exists)
        app.navigationBars["Club management"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["club.detail.error"].waitForExistence(timeout: 10), app.debugDescription)
        count(1)
    }
    func testTransientRefreshRetainsReadOnlyContextAndRetryRestoresReview() throws {
        launch("refreshConnection"); open("request", 703)
        app.buttons["club.management.detail.refresh"].tap()
        XCTAssertTrue(app.staticTexts["club.management.stale"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["club.management.joinMessage"].exists)
        XCTAssertFalse(app.buttons["club.management.approve.703"].isEnabled)
        XCTAssertFalse(app.buttons["club.management.reject.703"].isEnabled)
        count(0)
        app.buttons["club.management.detail.refresh"].tap()
        let fresh = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["club.management.approve.703"])
        XCTAssertEqual(XCTWaiter.wait(for: [fresh], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["club.management.stale"].exists)
        _ = prepare("approve", target: 703)
        try cancelReview("Approve application")
        count(0)
    }
    func testTransientListRefreshPreservesApplicantWithoutClaimingFreshness() {
        launch("refreshConnection")
        XCTAssertTrue(app.buttons["club.management.request.703"].waitForExistence(timeout: 5))
        app.buttons["club.management.refresh"].tap()
        XCTAssertTrue(app.staticTexts["club.management.stale"].waitForExistence(timeout: 5))
        open("request", 703)
        XCTAssertTrue(app.staticTexts["club.management.joinMessage"].exists)
        XCTAssertFalse(app.buttons["club.management.approve.703"].isEnabled)
        count(0)
    }
    func testDeniedAndMalformedRefreshClearPrivateApplicantData() {
        for scenario in ["refreshForbidden", "refreshMalformed"] {
            launch(scenario); open("request", 703)
            app.buttons["club.management.detail.refresh"].tap()
            let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["club.management.joinMessage"])
            XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
            XCTAssertFalse(app.buttons["club.management.approve.703"].exists)
            XCTAssertFalse(app.staticTexts["club.management.stale"].exists)
            count(0); app.terminate()
        }
    }
    func testRoleOnlyChangeClearsStaleApplicantWithoutAccountChange() {
        launch("refreshRoleChange"); open("request", 703)
        app.buttons["club.management.detail.refresh"].tap()
        XCTAssertTrue(app.staticTexts["club.management.stale"].waitForExistence(timeout: 5))
        app.buttons["club.management.roleChange"].tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["club.management.joinMessage"])
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
        XCTAssertEqual(app.buttons["club.management.switch"].value as? String, "account=701;epoch=0")
        XCTAssertFalse(app.buttons["club.management.request.703"].exists)
        XCTAssertFalse(app.buttons["club.management.confirm"].exists)
        count(0)
    }
    func testRoleOnlyChangeDoesNotClearUnknownWriteLock() {
        launch("unknownRoleChange"); open("request", 703)
        submit(prepare("approve", target: 703)); count(1)
        XCTAssertTrue(app.staticTexts["club.management.unknown"].waitForExistence(timeout: 10))
        app.buttons["club.management.roleChange"].tap()
        XCTAssertTrue(app.navigationBars["Club management"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Application details"].exists)
        XCTAssertFalse(app.staticTexts["club.management.joinMessage"].exists)
        XCTAssertFalse(element("club.management.detail.loading").exists)
        XCTAssertTrue(app.staticTexts["club.management.unknown"].exists)
        app.buttons["club.management.refresh"].tap()
        XCTAssertFalse(app.buttons["club.management.request.703"].exists)
        XCTAssertTrue(app.staticTexts["club.management.unknown"].exists)
        count(1)
        // Restoring the same role is not evidence that an unknown write failed.
        app.buttons["club.management.roleChange"].tap()
        XCTAssertTrue(app.staticTexts["club.management.unknown"].waitForExistence(timeout: 5))
        let refresh = app.buttons["club.management.refresh"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        refresh.tap()
        XCTAssertFalse(app.buttons["club.management.request.703"].exists)
        XCTAssertFalse(app.buttons["club.management.confirm"].exists)
        XCTAssertTrue(app.staticTexts["club.management.unknown"].exists)
        count(1)
    }


    func testInterruptedRefreshClearsLoadingAndLateFailureCannotReplaceFreshList() {
        launch("refreshDelayed"); open("request", 703)
        app.buttons["club.management.detail.refresh"].tap()
        XCTAssertTrue(element("club.management.detail.loading").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["club.management.releaseRead"].waitForExistence(timeout: 5))
        app.navigationBars["Application details"].buttons.firstMatch.tap()
        let refresh = app.buttons["club.management.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5)); XCTAssertTrue(refresh.isEnabled)
        open("request", 703)
        XCTAssertFalse(app.buttons["club.management.approve.703"].isEnabled)
        app.buttons["club.management.detail.refresh"].tap()
        let fresh = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["club.management.approve.703"])
        XCTAssertEqual(XCTWaiter.wait(for: [fresh], timeout: 5), .completed)
        app.buttons["club.management.releaseRead"].tap()
        let completedRead = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1"), object: app.staticTexts["club.management.finishedReads"])
        XCTAssertEqual(XCTWaiter.wait(for: [completedRead], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["club.management.stale"].exists)
        XCTAssertTrue(app.buttons["club.management.approve.703"].isEnabled)
        count(0)
    }
    func testRoleABAWhileReadPendingCannotRestoreOldReview() throws {
        for scenario in ["refreshRoleABA", "prepareRoleABA"] {
            launch(scenario); open("request", 703)
            app.buttons[scenario == "refreshRoleABA" ? "club.management.detail.refresh" : "club.management.approve.703"].tap()
            XCTAssertTrue(app.buttons["club.management.releaseRead"].waitForExistence(timeout: 5))
            app.buttons["club.management.roleChange"].tap()
            XCTAssertTrue(app.navigationBars["Club management"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars["Application details"].exists)
            XCTAssertFalse(app.staticTexts["club.management.joinMessage"].exists)
            XCTAssertFalse(element("club.management.detail.loading").exists)
            XCTAssertFalse(app.buttons["club.management.confirm"].exists)
            XCTAssertFalse(app.buttons["club.management.request.703"].exists)
            app.buttons["club.management.roleChange"].tap()
            XCTAssertTrue(app.buttons["club.management.request.703"].waitForExistence(timeout: 5))
            app.buttons["club.management.releaseRead"].tap()
        let completedRead = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "1"), object: app.staticTexts["club.management.finishedReads"])
        XCTAssertEqual(XCTWaiter.wait(for: [completedRead], timeout: 5), .completed)
            XCTAssertFalse(app.buttons["club.management.confirm"].exists)
            XCTAssertFalse(app.staticTexts["club.management.stale"].exists)
            open("request", 703)
            _ = prepare("approve", target: 703)
            try cancelReview("Approve application")
            count(0); app.terminate()
        }
    }
    func testCancelThenSwitchAccountSendsNothing() throws {
        launch("owner"); open("request", 703)
        _ = prepare("approve", target: 703)
        try cancelReview("Approve application")
        let accountSwitch = app.buttons["club.management.switch"]
        XCTAssertEqual(accountSwitch.value as? String, "account=701;epoch=0", app.debugDescription)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: accountSwitch)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
        accountSwitch.tap()
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "account=702;epoch=1"), object: accountSwitch)
        XCTAssertEqual(XCTWaiter.wait(for: [replaced], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(app.navigationBars["Club management"].waitForExistence(timeout: 5), app.debugDescription)
        count(0)
        XCTAssertFalse(app.navigationBars["Application details"].exists, app.debugDescription)
        XCTAssertFalse(app.navigationBars["Approve application"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["club.management.confirm"].exists, app.debugDescription)
    }


}
