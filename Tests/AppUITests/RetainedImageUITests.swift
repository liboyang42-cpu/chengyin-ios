import XCTest
final class RetainedImageUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<10 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func launch(_ mode: String = "success", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--retained-images-fixture", mode, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    func testUploadByteCountUsesSelectedLanguageInProductionReview() {
        for language in ["en", "zh-Hans"] {
            let app = XCUIApplication()
            // Persist an explicit app preference opposite to the simulated OS language.
            // Relaunch into the production review without resetting that preference.
            let systemLanguage = language == "en" ? "zh-Hans" : "en"
            let systemLocale = language == "en" ? "zh_CN" : "en_US"
            let arguments = ["--uitesting-market", "US", "-AppleLanguages", "(\(systemLanguage))", "-AppleLocale", systemLocale]
            app.launchArguments = ["--uitesting-reset-language"] + arguments
            app.launch()
            defer { attachFailureScreenshot(self, app: app); app.terminate() }
            XCTAssertTrue(app.buttons["welcome.settings"].waitForExistence(timeout: 5))
            app.buttons["welcome.settings"].tap()
            let choice = app.buttons[language == "en" ? "English" : "简体中文"]
            XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
            XCTAssertTrue(app.navigationBars[language == "en" ? "Settings" : "设置"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["region.market.value"].label, "US")
            app.terminate()
            app.launchArguments = ["--retained-images-fixture", "success"] + arguments
            app.launch()
            XCTAssertTrue(app.buttons["image.retained.fixtureSelect"].waitForExistence(timeout: 5))
            app.buttons["image.retained.fixtureSelect"].tap()
            let count = app.staticTexts["image.retained.byteCount"]
            reveal(count, in: app)
            let prefix = language == "en" ? "Upload size (bytes): " : "上传大小（字节）："
            XCTAssertTrue(count.label.hasPrefix(prefix), count.label)
            XCTAssertTrue(count.label.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }, count.label)
            XCTAssertFalse(count.label.contains("image.retained.byteCount"))
            XCTAssertFalse(app.buttons["image.retained.use"].exists)
        }
    }
    func testSelectionUploadAndUseAreSeparate() {
        let app = launch(); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        XCTAssertTrue(app.buttons["image.retained.select"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["image.retained.select"].isEnabled)
        app.buttons["image.retained.fixtureSelect"].tap()
        reveal(app.buttons["image.retained.confirmUpload"], in: app)
        XCTAssertFalse(app.buttons["image.retained.use"].exists)
        app.buttons["image.retained.confirmUpload"].tap()
        XCTAssertTrue(app.buttons["image.retained.use"].waitForExistence(timeout: 3))
        app.buttons["image.retained.use"].tap()
        XCTAssertTrue(app.staticTexts["image.retained.fixtureApplied"].exists)
    }
    func testUnknownUploadCannotBeRetried() {
        let app = launch("unknown"); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        XCTAssertTrue(app.buttons["image.retained.fixtureSelect"].waitForExistence(timeout: 5))
        app.buttons["image.retained.fixtureSelect"].tap()
        reveal(app.buttons["image.retained.confirmUpload"], in: app)
        app.buttons["image.retained.confirmUpload"].tap()
        XCTAssertTrue(app.staticTexts["image.retained.unknown"].waitForExistence(timeout: 3))
        app.buttons["image.retained.fixtureSelect"].tap()
        XCTAssertFalse(app.buttons["image.retained.confirmUpload"].exists)
        XCTAssertFalse(app.buttons["image.retained.use"].exists)
    }
    func testChineseAndAccessibilityLabels() {
        let app = launch(language: "zh-Hans"); defer { attachFailureScreenshot(self, app: app); app.terminate() }
        XCTAssertTrue(app.buttons["image.retained.select"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["image.retained.select"].label, "选择照片")
        app.buttons["image.retained.fixtureSelect"].tap()
        let preview = app.images["所选照片预览"]
        reveal(preview, in: app)
        XCTAssertEqual(preview.label, "所选照片预览")
        XCTAssertFalse(app.buttons["image.retained.use"].exists)
    }
}
