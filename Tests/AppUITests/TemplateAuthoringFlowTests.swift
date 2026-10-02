import XCTest

/// Authored synthetic flows only. No UI test was run in the Linux authoring workspace.
/// Mount TemplateAuthoringFixtureHostView for --ui-template-authoring in the Debug app.
@MainActor final class TemplateAuthoringFlowTests: XCTestCase {
    private func app(_ extras: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-template-authoring", "-AppleLanguages", "(en)"] + extras; app.launch(); return app
    }
    private func tap(_ id: String, in app: XCUIApplication) {
        let button = app.buttons[id]
        for _ in 0..<15 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 3), id); XCTAssertTrue(button.isHittable, id); button.tap()
    }
    private func edit(_ app: XCUIApplication) { tap("templateAuthor.begin", in: app); tap("templateAuthor.continue", in: app) }
    func testCreationStepsReplaceBackStack() {
        let app = app(); edit(app); XCTAssertTrue(app.textFields["templateAuthor.field.title"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.begin"].exists); XCTAssertFalse(app.buttons["templateAuthor.continue"].exists)
    }
    func testBlankNameDisablesContinue() {
        let app = app(["--template-author-blank"]); tap("templateAuthor.begin", in: app)
        XCTAssertFalse(app.buttons["templateAuthor.continue"].isEnabled)
    }
    func testLocalSaveHasExplicitDeviceOnlyResult() {
        let app = app(); edit(app); tap("templateAuthor.saveLocal", in: app)
        XCTAssertTrue(app.staticTexts["Saved securely on this device for this account."].exists)
    }
    func testReviewCancellationCannotSubmit() {
        let app = app(); edit(app); tap("templateAuthor.reviewPublish", in: app); tap("templateAuthor.cancelReview", in: app)
        XCTAssertFalse(app.buttons["templateAuthor.confirmSimulation"].exists)
    }
    func testSyntheticSubmissionNeverClaimsPublication() {
        let app = app(); edit(app); tap("templateAuthor.reviewPublish", in: app); tap("templateAuthor.confirmSimulation", in: app)
        XCTAssertTrue(app.staticTexts["Simulation completed. No template was saved to a server or published."].waitForExistence(timeout: 3))
    }
    func testProductionDisabledReviewHasNoConfirmButton() {
        let app = app(["--template-author-disabled"]); edit(app); tap("templateAuthor.reviewPublish", in: app)
        XCTAssertFalse(app.buttons["templateAuthor.confirmSimulation"].exists)
    }
    func testUnknownSubmissionRemainsLockedAfterReopen() {
        let app = app(["--template-author-unknown"]); edit(app); tap("templateAuthor.reviewPublish", in: app); tap("templateAuthor.confirmSimulation", in: app)
        tap("templateAuthor.fixture.reopen", in: app)
        XCTAssertFalse(app.buttons["templateAuthor.begin"].isEnabled)
        XCTAssertTrue(app.staticTexts["templateAuthor.status"].exists)
    }
    func testSignoutErasesEditorAndReview() {
        let app = app(); edit(app); tap("templateAuthor.fixture.signOut", in: app)
        XCTAssertTrue(app.staticTexts["templateAuthor.signIn"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["templateAuthor.field.title"].exists)
    }
    func testSavedDraftRestoreIsExplicit() {
        let app = app(); edit(app); tap("templateAuthor.saveLocal", in: app); tap("templateAuthor.fixture.reopen", in: app)
        XCTAssertTrue(app.buttons["templateAuthor.restore"].exists); tap("templateAuthor.restore", in: app)
        XCTAssertTrue(app.textFields["templateAuthor.field.title"].exists)
    }
    func testChineseAndLargeTextCanReachReview() {
        let app = app(["-AppleLanguages", "(zh-Hans)", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        edit(app); tap("templateAuthor.reviewPublish", in: app); XCTAssertTrue(app.buttons["templateAuthor.cancelReview"].exists)
    }
}
