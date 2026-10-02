import XCTest

/// Authored for the additive DEBUG --uitesting-module square-workspace host. Apple runtime NOT_RUN.
final class SquareWorkspaceFlowTests: XCTestCase {
    private func launch(chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-module", "square-workspace", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)"]
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
        let app = launch(chinese: true); defer { app.terminate() }
        XCTAssertTrue(app.textViews["squareWorkspace.body"].waitForExistence(timeout: 5))
        let field = app.textViews["squareWorkspace.body"]; field.tap(); field.typeText("Local only")
        for _ in 0..<8 { if app.buttons["squareWorkspace.saveLocal"].isHittable { break }; app.swipeUp() }
        app.buttons["squareWorkspace.saveLocal"].tap()
        XCTAssertTrue(app.staticTexts["已保存在本机"].exists)
    }
}
