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
    private func openLegal(_ type: String, rootTitle: String, file: StaticString = #filePath, line: UInt = #line) {
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertTrue(app.navigationBars[rootTitle].exists, app.debugDescription, file: file, line: line)
        let button = form.buttons["settingsNative.openLegal.\(type)"]
        // At accessibility5, Form does not expose the offscreen legal rows yet.
        // Wait for the root form, then reveal the row before asserting its existence.
        for _ in 0..<12 { if button.exists && button.isHittable { break }; form.swipeUp() }
        XCTAssertTrue(button.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(button.isHittable, app.debugDescription, file: file, line: line)
        button.tap()
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
            let rootTitle = language == "en" ? "Settings" : "设置"
            app.launchArguments = ["--uitesting-reset-language", "--uitesting-market", "US", "--uitesting-module", "settingsNative", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-max-text", "--uitesting-reduce-motion"]
            if language == "zh-Hans" { app.launchArguments.append("--uitesting-dark") }
            app.launch()
            assertFixtureEnvironment(in: app, colorScheme: language == "zh-Hans" ? "dark" : nil, dynamicTypeSize: "accessibility5")
            openLegal("user_agreement", rootTitle: rootTitle)
            XCTAssertTrue(app.staticTexts["settingsNative.legal.missing"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["settingsNative.legal.loading"].exists)
            XCTAssertFalse(app.buttons["Accept"].exists); XCTAssertFalse(app.buttons["同意"].exists)
            attachFixtureScreenshot(self, app: app, name: "Settings legal missing accessibility5 \(language)")
            app.navigationBars.buttons.firstMatch.tap()
            openLegal("privacy_policy", rootTitle: rootTitle)
            XCTAssertTrue(app.staticTexts["settingsNative.legal.missing"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["settingsNative.legal.version"].exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "settingsNative.")).firstMatch.exists)
            app.terminate()
        }
    }
}
