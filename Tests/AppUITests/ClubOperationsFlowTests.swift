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
        let control = reveal(id)
        XCTAssertTrue(control.exists, app.debugDescription)
        XCTAssertTrue(control.isHittable, app.debugDescription); control.tap()
    }
    private func reveal(_ id: String) -> XCUIElement {
        let control = element(id)
        for _ in 0..<14 { if control.exists && control.isHittable { return control }; app.swipeUp() }
        for _ in 0..<14 { if control.exists && control.isHittable { return control }; app.swipeDown() }
        return control
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
        tap("club.ops.readBack"); XCTAssertTrue(element("club.ops.outcomeUnknown").exists)
        tap("club.ops.close"); app.buttons["Leave form"].tap(); tap("club.ops.openManage")
        XCTAssertTrue(element("club.ops.outcomeUnknown").waitForExistence(timeout: 5)); count(1)
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
        XCTAssertTrue(app.staticTexts["Fixture member (#704)"].waitForExistence(timeout: 5))
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
        tap("club.ops.switchAccount")
        XCTAssertFalse(element("club.ops.acknowledged").exists)
    }
}
