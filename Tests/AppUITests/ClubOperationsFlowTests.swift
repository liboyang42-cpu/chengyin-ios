import XCTest

/// Authored offline scenarios. These are not backend or permission-change acceptance.
final class ClubOperationsFlowTests: XCTestCase {
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
    func testOwnerSettingRequiresReviewAndSingleConfirmation() {
        launch(); reviewSetting(); XCTAssertTrue(element("club.ops.reviewSheet").waitForExistence(timeout: 5))
        tap("club.ops.confirm"); count(1)
        XCTAssertTrue(reveal("club.ops.acknowledged").exists)
    }
    func testCancelReviewSendsNothing() {
        launch(); reviewSetting(); tap("club.ops.cancelReview"); count(0)
    }
    func testUnknownReadbackDoesNotUnlockAndReopenDoesNotReplay() {
        launch("unknown"); reviewSetting(); tap("club.ops.confirm"); count(1)
        tap("club.ops.readBack"); XCTAssertTrue(reveal("club.ops.outcomeUnknown").exists)
        XCTAssertFalse(element("club.ops.acknowledged").exists); count(1)
        tap("club.ops.close"); app.buttons["Leave form"].tap(); tap("club.ops.openManage")
        XCTAssertTrue(reveal("club.ops.outcomeUnknown").exists); count(1)
        _ = reveal("club.ops.setting.publicVisible")
        let setting = app.buttons["club.ops.setting.publicVisible"].firstMatch
        XCTAssertTrue(setting.exists); XCTAssertFalse(setting.isEnabled)
    }
    func testAdminProfileHasNoOwnerSettingsOrRoleActions() {
        launch("admin"); tap("club.ops.openManage")
        XCTAssertTrue(element("club.ops.field.name").waitForExistence(timeout: 5))
        XCTAssertFalse(element("club.ops.setting.publicVisible").exists); XCTAssertFalse(element("club.ops.member.704").exists)
    }
    func testOrdinaryViewerIsDeniedAndCreateRoleGated() {
        launch("ordinary"); tap("club.ops.openManage"); XCTAssertTrue(reveal("club.ops.error").exists); count(0)
        tap("club.ops.close"); tap("club.ops.openCreate")
        XCTAssertFalse(element("club.ops.reviewProfile").exists)
    }
    func testTwoClubLimitPreventsCreateForm() {
        launch("limit"); tap("club.ops.openCreate")
        XCTAssertTrue(app.staticTexts["You already own two clubs. Manage an existing club instead."].waitForExistence(timeout: 5))
        XCTAssertFalse(element("club.ops.reviewProfile").exists); count(0)
    }
    func testUnverifiedReviewContainsNoSubmitControl() {
        launch("unverified"); reviewSetting()
        XCTAssertTrue(element("club.ops.reviewSheet").waitForExistence(timeout: 5)); XCTAssertFalse(element("club.ops.confirm").exists)
    }
    func testPopulatedMemberQuotaKeepsItsVisibleLabelInBothLanguages() {
        for chinese in [false, true] {
            launch(chinese: chinese); tap("club.ops.openManage")
            let field = element("club.ops.field.quota")
            XCTAssertTrue(revealFixtureElement(field, in: app), app.debugDescription)
            XCTAssertEqual(field.value as? String, "4")
            let label = app.staticTexts["clubQuota.visibleLabel"]
            XCTAssertTrue(label.exists, app.debugDescription)
            XCTAssertEqual(label.label, chinese ? "成员保留名额" : "Reserved member places")
            count(0)
            attachFixtureScreenshot(self, app: app, name: chinese ? "Populated member quota Chinese" : "Populated member quota English")
            app.terminate()
        }
    }
    func testMemberRoleConfirmationIdentifiesTarget() {
        launch(); tap("club.ops.openManage")
        let member = app.buttons["club.ops.member.704"].firstMatch
        func clearOfBottomToolbar() -> Bool {
            guard member.exists && member.isHittable else { return false }
            let topOfToolbar = app.toolbars.allElementsBoundByIndex
                .filter { $0.exists && $0.frame.minY > app.frame.midY }
                .map { $0.frame.minY }.min() ?? app.frame.maxY
            return member.frame.maxY < topOfToolbar
        }
        for _ in 0..<10 { if clearOfBottomToolbar() { break }; app.swipeUp() }
        XCTAssertTrue(clearOfBottomToolbar(), app.debugDescription)
        tap("club.ops.member.704")
        XCTAssertTrue(element("club.ops.reviewSheet").waitForExistence(timeout: 5), app.debugDescription)
        // LabeledContent exposes a combined localized label and value.
        let target = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fixture member (#704)")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        tap("club.ops.confirm"); count(1)
    }
    func testChineseProfileValidationAndDiscard() {
        launch(chinese: true); tap("club.ops.openCreate"); tap("club.ops.reviewProfile")
        XCTAssertTrue(reveal("club.ops.error").exists); count(0)
        let name = element("club.ops.field.name"); app.swipeDown(); name.tap(); name.typeText("本地社群")
        tap("club.ops.close"); app.buttons["离开表单"].tap()
        XCTAssertTrue(element("club.ops.fixtureNotice").exists)
    }
    func testAccountSwitchDuringDelayedWriteKeepsOldOutcomeHidden() {
        launch("delayed"); reviewSetting(); tap("club.ops.confirm"); count(1)
        XCTAssertEqual(writeCounter.value as? String, "account=701;finished=0")
        tap("club.ops.switchAccount")
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let counters = self.visibleWriteCounters
            return counters.count == 1 && counters[0].value as? String == "account=702;finished=1"
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(element("club.ops.field.name").waitForExistence(timeout: 5))
        XCTAssertFalse(element("club.ops.acknowledged").exists); count(1)
        tap("club.ops.switchAccount")
        XCTAssertTrue(reveal("club.ops.outcomeUnknown").exists); count(1)
    }
}
