import XCTest

/// Authored for the additive DEBUG --uitesting-module square-workspace host. Apple runtime NOT_RUN.
final class SquareWorkspaceFlowTests: XCTestCase {
    private var activeApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: activeApp)
        if let app = activeApp, (testRun?.totalFailureCount ?? 0) > 0 {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Square workspace failure hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        if let app = activeApp, app.state != .notRunning { app.terminate() }
        activeApp = nil
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { break }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.exists, "Expected control \(element.identifier): " + app.debugDescription)
        XCTAssertTrue(element.isHittable, "Expected hittable control \(element.identifier): " + app.debugDescription)
    }
    private func launch(chinese: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "square-workspace", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"] + extra
        activeApp = app; app.launch(); return app
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
        reveal(first, in: app)
        XCTAssertEqual(first.label, "Resume editing", app.debugDescription)
        XCTAssertTrue(app.buttons["squareWorkspace.discard.synthetic-square-001"].exists)
        first.tap()
        let state = app.staticTexts["fixture.workspaceRecovery.state"]
        expectation(for: NSPredicate(format: "label == %@", "Synthetic recovery suspended"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        let second = app.buttons["squareWorkspace.resume.synthetic-square-002"]
        XCTAssertTrue(revealFixtureElement(second, in: app, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(second.exists); XCTAssertFalse(second.isEnabled)
        let newDraft = app.buttons["squareWorkspace.newDraft"]
        XCTAssertTrue(revealFixtureElement(newDraft, in: app, towardTop: true, maximumSwipes: 16, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(newDraft.exists); XCTAssertFalse(newDraft.isEnabled)
        // Follow the exact editor identifier across disabled/enabled AX representations.
        let editor = app.descendants(matching: .any)["squareWorkspace.body"].firstMatch
        XCTAssertTrue(revealFixtureElement(editor, in: app, towardTop: true, maximumSwipes: 16, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(editor.exists, app.debugDescription); XCTAssertFalse(editor.isEnabled, app.debugDescription)
        XCTAssertEqual(app.staticTexts["fixture.workspaceRecovery.requests"].label, "1")
        attachFixtureScreenshot(self, app: app, name: "Saved draft recovery serializes New Draft and text edits - synthetic suspended read")
        let release = app.buttons["fixture.workspaceRecovery.release"]
        XCTAssertTrue(release.isHittable); release.tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: editor)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(editor.value as? String, "Saved first recovery draft")
        reveal(newDraft, in: app); XCTAssertTrue(newDraft.isEnabled); newDraft.tap()
        XCTAssertTrue(revealFixtureElement(editor, in: app, towardTop: true, maximumSwipes: 16), app.debugDescription)
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        editor.typeText("New text after recovery")
        XCTAssertEqual(editor.value as? String, "New text after recovery")
        XCTAssertEqual(app.staticTexts["fixture.workspaceRecovery.requests"].label, "1")
    }
}
