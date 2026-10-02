import XCTest

/// Authored offline scenarios. These are not backend or permission-change acceptance.
final class ClubOperationsFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
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
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", String(value)), object: element("club.ops.writeCount"))
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
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
    func testMemberRoleConfirmationIdentifiesTarget() {
        launch(); tap("club.ops.openManage"); tap("club.ops.member.704")
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
        XCTAssertEqual(element("club.ops.writeCount").value as? String, "account=701;finished=0")
        tap("club.ops.switchAccount")
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "account=702;finished=1"), object: element("club.ops.writeCount"))
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(element("club.ops.field.name").waitForExistence(timeout: 5))
        XCTAssertFalse(element("club.ops.acknowledged").exists); count(1)
        tap("club.ops.switchAccount")
        XCTAssertTrue(reveal("club.ops.outcomeUnknown").exists); count(1)
    }
}
