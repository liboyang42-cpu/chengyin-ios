import XCTest

/// Authored synthetic flows only. No UI test was run in the Linux authoring workspace.
/// Mount TemplateAuthoringFixtureHostView for --ui-template-authoring in the Debug app.
@MainActor final class TemplateAuthoringFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func app(_ extras: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-template-authoring", "--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + extras
        app.launch(); return app
    }
    private func tap(_ id: String, in app: XCUIApplication) {
        let button = app.buttons[id]
        if id.hasPrefix("templateAuthor.fixture.") || id == "templateAuthor.cancelReview" {
            XCTAssertTrue(button.waitForExistence(timeout: 5), id); XCTAssertTrue(button.isHittable, id)
        } else {
            XCTAssertTrue(revealFixtureElement(button, in: app, maximumSwipes: 50), id + "\n" + app.debugDescription)
        }
        button.tap()
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
        let status = app.staticTexts["templateAuthor.status"]
        XCTAssertTrue(revealFixtureElement(status, in: app, requiresHittable: false))
        let unknown = "The submission outcome is unknown. Retrying and deleting this draft are blocked. No receipt lookup contract is available."
        XCTAssertEqual(status.label, unknown)
        tap("templateAuthor.fixture.reopen", in: app)
        let restore = app.buttons["templateAuthor.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); XCTAssertFalse(restore.isEnabled)
        let begin = app.buttons["templateAuthor.begin"]
        XCTAssertTrue(revealFixtureElement(begin, in: app, requiresHittable: false)); XCTAssertFalse(begin.isEnabled)
        XCTAssertTrue(revealFixtureElement(status, in: app, requiresHittable: false)); XCTAssertEqual(status.label, unknown)
        XCTAssertFalse(app.buttons["templateAuthor.confirmSimulation"].exists)
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
        let app = app(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], language: "zh-Hans")
        XCTAssertTrue(app.navigationBars["创作玩法模板"].waitForExistence(timeout: 5))
        edit(app); tap("templateAuthor.reviewPublish", in: app)
        XCTAssertTrue(app.navigationBars["确认提交内容"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["templateAuthor.cancelReview"].exists)
    }
}
