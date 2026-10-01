import XCTest

/// Synthetic DEBUG fixture only. Host must route --uitesting-club-management-fixture.
final class ClubManagementFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app); app.terminate(); app = nil }
    private func launch(_ scenario: String) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-club-management-fixture", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["Offline synthetic club management fixture"].waitForExistence(timeout: 10))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func count(_ value: Int) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", String(value)), object: element("club.management.writes"))
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }
    private func open(_ type: String, _ id: Int) {
        let row = element("club.management.\(type).\(id)")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<5 { if row.isHittable { break }; app.swipeUp() }
        row.tap()
    }
    private func prepare(_ action: String, target: Int) -> XCUIElement {
        let button = app.buttons["club.management.\(action).\(target)"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        let sheet = app! // SwiftUI modal can expose Other rather than XCUIElementTypeSheet.
        let title = action == "approve" ? "Approve application" : action == "reject" ? "Reject application" : "Remove member"
        XCTAssertTrue(sheet.navigationBars[title].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(sheet.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Fixture club (#81)")).firstMatch.exists,app.debugDescription)
        let name = target == 703 ? "Fixture applicant" : "Fixture member"
        XCTAssertTrue(sheet.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","\(name) (#\(target))")).firstMatch.exists,app.debugDescription)
        count(0)
        return sheet
    }
    private func submit(_ sheet: XCUIElement) {
        let matches = sheet.buttons.matching(identifier: "club.management.confirm")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            matches.allElementsBoundByIndex.contains { $0.exists && $0.isEnabled && $0.isHittable }
        }, object: sheet)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        guard let leaf = matches.allElementsBoundByIndex.reversed().first(where: { $0.exists && $0.isEnabled && $0.isHittable }) else { XCTFail("Missing actionable sheet button"); return }
        leaf.tap()
    }
    func testApproveRequiresTargetConfirmation() {
        launch("owner"); open("request", 703)
        submit(prepare("approve", target: 703)); count(1)
    }
    func testRejectCancelSendsNothing() {
        launch("admin"); open("request", 703)
        let sheet = prepare("reject", target: 703)
        sheet.buttons["Cancel"].firstMatch.tap(); count(0)
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
    func testCancelThenSwitchAccountSendsNothing() {
        launch("owner"); open("request", 703)
        _ = prepare("approve", target: 703)
        // Dismiss before using fixture controls, as a real account replacement comes
        // from the host rather than a control behind a modal presentation.
        app.buttons["Cancel"].firstMatch.tap()
        app.buttons["club.management.switch"].tap(); count(0)
        XCTAssertFalse(app.buttons["club.management.confirm"].exists)
    }
}
