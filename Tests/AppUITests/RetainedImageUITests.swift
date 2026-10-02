import XCTest
final class RetainedImageUITests: XCTestCase {
    private func launch(_ mode: String = "success", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--retained-images-fixture", mode, "-AppleLanguages", "(\(language))"]
        app.launch(); return app
    }
    func testSelectionUploadAndUseAreSeparate() {
        let app = launch()
        XCTAssertTrue(app.buttons["image.retained.select"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["image.retained.select"].isEnabled)
        app.buttons["image.retained.fixtureSelect"].tap()
        XCTAssertTrue(app.buttons["image.retained.confirmUpload"].exists)
        XCTAssertFalse(app.buttons["image.retained.use"].exists)
        app.buttons["image.retained.confirmUpload"].tap()
        XCTAssertTrue(app.buttons["image.retained.use"].waitForExistence(timeout: 3))
        app.buttons["image.retained.use"].tap()
        XCTAssertTrue(app.staticTexts["image.retained.fixtureApplied"].exists)
    }
    func testUnknownUploadCannotBeRetried() {
        let app = launch("unknown")
        XCTAssertTrue(app.buttons["image.retained.fixtureSelect"].waitForExistence(timeout: 5))
        app.buttons["image.retained.fixtureSelect"].tap(); app.buttons["image.retained.confirmUpload"].tap()
        XCTAssertTrue(app.staticTexts["image.retained.unknown"].waitForExistence(timeout: 3))
        app.buttons["image.retained.fixtureSelect"].tap()
        XCTAssertFalse(app.buttons["image.retained.confirmUpload"].exists)
        XCTAssertFalse(app.buttons["image.retained.use"].exists)
    }
    func testChineseAndAccessibilityLabels() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["image.retained.select"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["image.retained.select"].label, "选择照片")
        app.buttons["image.retained.fixtureSelect"].tap()
        XCTAssertTrue(app.images["所选照片预览"].exists)
    }
}
