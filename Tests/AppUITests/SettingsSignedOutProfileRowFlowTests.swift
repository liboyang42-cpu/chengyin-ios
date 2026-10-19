import XCTest

/// pages/shezhi signed-out 个人资料 row (w2-03): explains sign-in, never opens the editor.
final class SettingsSignedOutProfileRowFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    func testGuestSettingsShowSignInRowInsteadOfProfile() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let settings = app.buttons["welcome.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settingsNative.profileSignedOut"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["登录后查看账号信息"].exists)
        XCTAssertFalse(app.buttons["settingsNative.openProfile"].exists)
        XCTAssertFalse(app.buttons["settings.privacyLocation"].exists)
    }
}
