import XCTest

/// Authored offline scenarios. These are not backend or permission-change acceptance.
final class ClubProfileScopeFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: app)
        if (testRun?.totalFailureCount ?? 0) > 0 {
            let evidence = XCTAttachment(string: app.debugDescription)
            evidence.name = "Club operations failure accessibility hierarchy"; evidence.lifetime = .keepAlways; add(evidence)
        }
        app.terminate(); app = nil
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    // The toolbar wrapper may retain an earlier accessibilityValue after a scope change.
    // Read the Text leaf that displays the live fixture store's count and identity.
    private var visibleWriteCounters: [XCUIElement] {
        func visible(_ elements: [XCUIElement]) -> [XCUIElement] {
            elements.filter { $0.exists && $0.isHittable && !$0.frame.isEmpty && app.frame.contains($0.frame) }
        }
        // Run108 exposes both the covered root List and the foreground sheet's
        // counter. Resolve the leaf through its actual toolbar, never the covered
        // root or the stale accessibility value cached on a wrapping Other node.
        let presented = app.toolbars.staticTexts.matching(identifier: "club.ops.writeCount")
        if presented.count > 0 { return visible(presented.allElementsBoundByIndex) }
        return visible(app.staticTexts.matching(identifier: "club.ops.writeCount").allElementsBoundByIndex)
    }
    private var writeCounter: XCUIElement {
        let counters = visibleWriteCounters
        XCTAssertEqual(counters.count, 1, app.debugDescription)
        return counters.first ?? app.staticTexts["club.ops.writeCount"].firstMatch
    }
    private func launch(_ scenario: String = "owner", chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-club-operations", scenario]
        app.launch(); XCTAssertTrue(element("club.ops.fixtureNotice").waitForExistence(timeout: 10))
    }
    private func tap(_ id: String) {
        _ = reveal(id)
        let buttons = app.buttons.matching(identifier: id)
        guard let control = buttons.allElementsBoundByIndex.reversed().first(where: { $0.exists && $0.isHittable }) else {
            XCTFail("Missing presented button: \(id). \(app.debugDescription)"); return
        }
        XCTAssertTrue(control.isEnabled, app.debugDescription); control.tap()
    }
    private func reveal(_ id: String) -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(identifier: id)
        func visible() -> XCUIElement? {
            matches.allElementsBoundByIndex.reversed().first { $0.exists && $0.isHittable }
        }
        for _ in 0..<14 { if let control = visible() { return control }; app.swipeUp() }
        for _ in 0..<14 { if let control = visible() { return control }; app.swipeDown() }
        return matches.firstMatch
    }
    private func count(_ value: Int) {
        // The covered root List and foreground sheet toolbar both mount this ID.
        // Re-resolve the unique foreground Text leaf for each existing-budget poll.
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let counters = self.visibleWriteCounters
            return counters.count == 1 && counters[0].label == String(value)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, app.debugDescription)
    }
    private func reviewSetting() { tap("club.ops.openManage"); tap("club.ops.setting.publicVisible") }
    func testAdminDisplayOnlyReviewCancelsThenSavesOnce() {
        launch("admin"); tap("club.ops.openManage")
        let name = element("club.ops.field.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(" edited")
        tap("club.ops.reviewProfile")
        XCTAssertTrue(element("club.ops.reviewSheet").waitForExistence(timeout: 5))
        XCTAssertTrue(reveal("club.ops.confirm").exists)
        for id in ["club.ops.reviewSheet.prioritySignup", "club.ops.reviewSheet.quota", "club.ops.reviewSheet.joinPolicy"] {
            XCTAssertFalse(element(id).exists, app.debugDescription)
        }
        tap("club.ops.cancelReview"); count(0)
        tap("club.ops.reviewProfile"); tap("club.ops.confirm"); count(1)
        XCTAssertTrue(reveal("club.ops.acknowledged").exists)
    }
    func testOwnerProfileReviewRetainsOperatingFields() {
        launch(); tap("club.ops.openManage")
        let name = element("club.ops.field.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(" edited")
        tap("club.ops.reviewProfile")
        XCTAssertTrue(element("club.ops.reviewSheet").waitForExistence(timeout: 5))
        for id in ["club.ops.reviewSheet.prioritySignup", "club.ops.reviewSheet.quota", "club.ops.reviewSheet.joinPolicy"] {
            XCTAssertTrue(reveal(id).exists, app.debugDescription)
        }
        tap("club.ops.cancelReview"); count(0)
    }
}
