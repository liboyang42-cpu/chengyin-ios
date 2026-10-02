import XCTest

/// Offline DEBUG fixtures only. The fixture root does not construct AppSession,
/// a transport, a credential, or a real membership request.
final class ClubActionFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app); app.terminate(); app = nil }

    private func launch(_ scenario: String) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "--uitesting-club-action-fixture", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["club.action.fixture.notice"].waitForExistence(timeout: 10), app.debugDescription)
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, app.debugDescription, file: file, line: line)
        element.tap()
    }
    private func assertCount(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
        // Resolve the known text leaf rather than scanning every AX element. The
        // loaded CI simulator can take several seconds for a single snapshot; keep
        // the exact count predicate, with time for that read to finish.
        let counter = app.staticTexts.matching(identifier: "club.action.fixture.writeCount").firstMatch
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", String(count)),
                                                 object: counter)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 20), .completed, app.debugDescription, file: file, line: line)
    }
    private func assertMembership(_ status: String, file: StaticString = #filePath, line: UInt = #line) {
        let membership = app.staticTexts.matching(identifier: "club.action.serverMembership").firstMatch
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", status), object: membership)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed, app.debugDescription, file: file, line: line)
    }
    private func confirm(_ action: String) {
        let button = app.buttons["club.action." + action]
        reveal(button); tap(button)
        // iOS 26 presents this native confirmation as a popover containing a sheet.
        // Its accessibility tree exposes both a wrapper and the actionable button with
        // this identifier. Resolve a hittable descendant inside the actual dialog,
        // rather than asking the ambiguous application-wide query for one element.
        let dialog = app.sheets.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), app.debugDescription)
        let title = action == "apply" ? "Apply to join" : action == "leave" ? "Leave club" : "Join club"
        XCTAssertEqual(dialog.label, title)
        let target = dialog.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fixture club")).firstMatch
        XCTAssertTrue(target.exists, "The native dialog must name the club being changed")
        assertCount(0)
        let matches = dialog.buttons.matching(identifier: "club.action.confirm")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            matches.allElementsBoundByIndex.contains { $0.exists && $0.isEnabled && $0.isHittable }
        }, object: dialog)
        capture("Club confirmation before dispatch – " + action)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, app.debugDescription)
        guard let confirmation = matches.allElementsBoundByIndex.reversed().first(where: { $0.exists && $0.isEnabled && $0.isHittable }) else {
            XCTFail("No enabled, hittable confirmation button in the presented native sheet: " + app.debugDescription)
            return
        }
        XCTAssertEqual(confirmation.label, title)
        // The scoped candidate above is already enabled and hittable. Do not start
        // a second readiness deadline: slow AX reads can expire it before any tap.
        confirmation.tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testJoinRequiresConfirmationAndUsesServerMembership() {
        launch("join")
        assertCount(0)
        confirm("join")
        let leave = app.buttons["club.action.leave"]
        XCTAssertTrue(leave.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(leave.isEnabled)
        assertCount(1)
        XCTAssertFalse(app.buttons["club.action.join"].exists)
        assertMembership("Joined")
        capture("Club joined – synthetic server readback")
    }
    func testApplicationStaysPendingWithoutMembershipAccess() {
        launch("apply")
        confirm("apply")
        assertCount(1)
        let pending = element("club.action.gated")
        XCTAssertTrue(pending.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(pending.label.localizedCaseInsensitiveContains("pending"), pending.label)
        XCTAssertFalse(app.buttons["club.action.leave"].exists)
        XCTAssertFalse(app.buttons["club.action.apply"].exists)
        assertMembership("Join request pending")
        let membersGate = element("club.members.gated")
        reveal(membersGate)
        XCTAssertTrue(membersGate.exists, app.debugDescription)
        XCTAssertFalse(app.buttons["club.openMembers"].exists)
        assertCount(1)
        capture("Club application remains pending – synthetic data")
    }
    func testUnknownOutcomeReadbackDoesNotUnlockOrRepeatAcrossRelogin() {
        launch("unknown")
        confirm("join")
        let unknown = element("club.action.unknown")
        XCTAssertTrue(unknown.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["club.action.join"].isEnabled)
        assertCount(1)
        let readback = app.buttons["club.action.readback"]
        reveal(readback); tap(readback)
        let leave = app.buttons["club.action.leave"]
        XCTAssertTrue(leave.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(leave.isEnabled, "A current Joined snapshot must not unlock an uncertain mutation")
        assertMembership("Joined")
        XCTAssertTrue(unknown.exists)
        assertCount(1)
        tap(app.buttons["club.action.fixture.signOut"])
        tap(app.buttons["club.action.fixture.signIn"])
        XCTAssertTrue(unknown.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(leave.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(leave.isEnabled, "Same-account relogin must retain the unknown-outcome lock")
        assertCount(1)
        capture("Unknown club request remains locked after readback and relogin")
    }
}
