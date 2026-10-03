import XCTest

/// Additional S1 regression coverage; no settings redesign or new local preference owner.
final class NativeSettingsReuseFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        for _ in 0..<12 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.isHittable, app.debugDescription, file: file, line: line); button.tap()
    }
    func testFollowSystemPersistsAcrossRelaunchWithoutChangingUSMarket() {
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-market", "US", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); tap("welcome.settings"); tap("简体中文")
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10))
        tap("跟随系统")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["region.market.value"].label, "US")
        tap("Done"); app.terminate()
        app.launchArguments = ["--uitesting-market", "US", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); tap("welcome.settings")
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["region.market.value"].label, "US")
        tap("完成"); tap("welcome.settings")
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10))
    }
    func testMaximumTextLegalMissingStateBackAndReopenInBothLanguages() {
        for language in ["en", "zh-Hans"] {
            app.launchArguments = ["--uitesting-reset-language", "--uitesting-market", "US", "--uitesting-module", "settingsNative", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--uitesting-reduce-motion"]
            if language == "zh-Hans" { app.launchArguments.append("--uitesting-dark") }
            app.launch(); tap("settingsNative.openLegal.user_agreement")
            XCTAssertTrue(app.staticTexts["settingsNative.legal.missing"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["settingsNative.legal.loading"].exists)
            XCTAssertFalse(app.buttons["Accept"].exists); XCTAssertFalse(app.buttons["同意"].exists)
            attachFixtureScreenshot(self, app: app, name: "Settings legal missing accessibility5 \(language)")
            app.navigationBars.buttons.firstMatch.tap()
            tap("settingsNative.openLegal.privacy_policy")
            XCTAssertTrue(app.staticTexts["settingsNative.legal.missing"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["settingsNative.legal.version"].exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "settingsNative.")).firstMatch.exists)
            app.terminate()
        }
    }
}
