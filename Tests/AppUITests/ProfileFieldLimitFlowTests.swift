import XCTest

/// gerenziliao 140-unit limits on 昵称 and 城市签名 (w2-03), using the existing profile-edit fixture.
final class ProfileFieldLimitFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func open(_ name: String) -> XCUIElement {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-profile-edit-fixture", "success"]
        app.launch()
        let row = app.buttons["profile.fieldEdit.open.\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let input = app.textFields["profile.edit.\(name)"]
        if input.waitForExistence(timeout: 3) { return input }
        let multiline = app.textViews["profile.edit.\(name)"]
        XCTAssertTrue(multiline.waitForExistence(timeout: 3)); return multiline
    }
    func testIntroductionOver140UnitsCannotBeApplied() {
        let field = open("introduction")
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(String(repeating: "x", count: 150))
        let counter = app.staticTexts["profile.edit.limit"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "150/140")
        XCTAssertFalse(app.buttons["profile.fieldEdit.apply"].isEnabled)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
        XCTAssertEqual(counter.label, "140/140")
        XCTAssertTrue(app.buttons["profile.fieldEdit.apply"].isEnabled)
    }
    func testNicknameShowsCounter() {
        let field = open("name")
        field.tap(); field.typeText("a")
        XCTAssertTrue(app.staticTexts["profile.edit.limit"].waitForExistence(timeout: 5))
    }
}
