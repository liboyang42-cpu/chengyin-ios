import XCTest

/// Authored for the additive DEBUG --uitesting-module square-workspace host. Apple runtime NOT_RUN.
final class SquareWorkspaceFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { break }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func launch(chinese: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "square-workspace", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"] + extra
        app.launch(); return app
    }
    func testDefaultWorkspaceHasNoEnabledNetworkActions() {
        let app = launch(); defer { app.terminate() }
        XCTAssertTrue(app.textViews["squareWorkspace.body"].waitForExistence(timeout: 5))
        for _ in 0..<8 { if app.buttons["squareWorkspace.review"].exists { break }; app.swipeUp() }
        XCTAssertFalse(app.buttons["squareWorkspace.review"].isEnabled)
        XCTAssertFalse(app.buttons["squareWorkspace.saveServer"].isEnabled)
        XCTAssertTrue(app.buttons["squareWorkspace.saveLocal"].isEnabled)
    }
    func testChineseComposerAndLocalDraftEntry() {
        let app = launch(chinese: true); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        XCTAssertTrue(app.textViews["squareWorkspace.body"].waitForExistence(timeout: 5))
        let field = app.textViews["squareWorkspace.body"]; field.tap(); field.typeText("Local only")
        let save = app.buttons["squareWorkspace.saveLocal"]
        reveal(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        // Verify the newly saved entry, not the fixture's pre-existing saved status.
        let savedBody = app.staticTexts.matching(NSPredicate(format: "label == %@", "Local only")).firstMatch
        reveal(savedBody, in: app)
        let status = app.staticTexts["squareWorkspace.status"]
        reveal(status, in: app, upwards: false)
        XCTAssertEqual(status.label, "已保存在本机", app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testSuspendedRecoveryDisablesNewDraftTypingAndCompetingResume() {
        let app = launch(extra: ["--uitesting-workspace-delayed-recovery"])
        defer { attachFailureScreenshot(self, app: app); app.terminate() }
        let first = app.buttons["squareWorkspace.resume.synthetic-square-001"]
        reveal(first, in: app); first.tap()
        let state = app.staticTexts["fixture.workspaceRecovery.state"]
        expectation(for: NSPredicate(format: "label == %@", "Synthetic recovery suspended"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        let second = app.buttons["squareWorkspace.resume.synthetic-square-002"]
        XCTAssertTrue(second.exists); XCTAssertFalse(second.isEnabled)
        let newDraft = app.buttons["squareWorkspace.newDraft"]
        for _ in 0..<10 { if newDraft.exists { break }; app.swipeDown() }
        XCTAssertTrue(newDraft.exists); XCTAssertFalse(newDraft.isEnabled)
        let editor = app.textViews["squareWorkspace.body"]
        for _ in 0..<10 { if editor.exists { break }; app.swipeDown() }
        XCTAssertTrue(editor.exists); XCTAssertFalse(editor.isEnabled)
        XCTAssertEqual(app.staticTexts["fixture.workspaceRecovery.requests"].label, "1")
        attachFixtureScreenshot(self, app: app, name: "Saved draft recovery serializes New Draft and text edits - synthetic suspended read")
        let release = app.buttons["fixture.workspaceRecovery.release"]
        XCTAssertTrue(release.isHittable); release.tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: editor)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(editor.value as? String, "Saved first recovery draft")
        reveal(newDraft, in: app); XCTAssertTrue(newDraft.isEnabled); newDraft.tap()
        reveal(editor, in: app, upwards: false); editor.tap(); editor.typeText("New text after recovery")
        XCTAssertEqual(editor.value as? String, "New text after recovery")
        XCTAssertEqual(app.staticTexts["fixture.workspaceRecovery.requests"].label, "1")
    }
}
