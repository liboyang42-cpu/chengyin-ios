import XCTest

/// Offline fixture for the mini pages/crop counterpart: synthetic drawn images, no picker, camera or upload.
final class MiniCropFlowTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "mini-crop"]
        app.launch(); return app
    }
    func testBatchWalksEachImageAndReportsPerImageResult() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["miniCrop.progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["miniCrop.progress"].label, "Crop 1/2")
        app.buttons["miniCrop.useOriginal"].tap()
        XCTAssertEqual(app.staticTexts["miniCrop.progress"].label, "Crop 2/2")
        app.buttons["miniCrop.confirm"].tap()
        // Untouched 1:1 crop of a 300x400 image selects the centered 300x300 square.
        XCTAssertTrue(app.staticTexts["miniCrop.outcome"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["miniCrop.outcome"].label, "original, crop 300x300")
    }
    func testCancelReturnsWithoutResults() {
        let app = launch()
        XCTAssertTrue(app.buttons["miniCrop.cancel"].waitForExistence(timeout: 5))
        app.buttons["miniCrop.cancel"].tap()
        XCTAssertEqual(app.staticTexts["miniCrop.outcome"].label, "cancelled")
    }
}
