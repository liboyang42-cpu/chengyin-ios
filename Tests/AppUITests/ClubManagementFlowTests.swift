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
    private func prepare(_ action: String, target: Int) -> XCUIElement {
        let button = app.buttons["club.management.\(action).\(target)"].firstMatch
        let detail = app.navigationBars[action == "remove" ? "Member details" : "Application details"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(detail.exists, app.debugDescription)
        XCTAssertTrue(button.isEnabled, app.debugDescription)
        button.tap()
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
