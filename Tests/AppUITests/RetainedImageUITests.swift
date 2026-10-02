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
