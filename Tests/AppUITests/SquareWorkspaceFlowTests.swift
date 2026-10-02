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
    private func launch(chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "square-workspace", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
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
}
