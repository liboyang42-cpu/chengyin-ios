import XCTest

/// Offline CN build only. No real provider, account, or network is used.
final class WeChatAppAuthFlowTests: XCTestCase {
    func testDormantBilingualEntryCanCloseAndReopen() {
        for language in ["en", "zh-Hans"] {
            let app = XCUIApplication()
            app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))"]
            app.launch()
            for _ in 0..<2 {
                XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout: 10))
                app.buttons["welcome.player"].tap()
                let button = app.buttons["auth.wechat.signIn"]
                XCTAssertTrue(button.waitForExistence(timeout: 5))
                XCTAssertFalse(button.isEnabled)
                XCTAssertTrue(app.staticTexts["auth.wechat.gate"].exists)
                XCTAssertTrue(app.buttons["auth.signIn"].exists)
                XCTAssertTrue(app.buttons["auth.otherChannels"].exists)
                app.buttons[language == "en" ? "Close" : "关闭"].tap()
            }
            app.terminate()
        }
    }
}
