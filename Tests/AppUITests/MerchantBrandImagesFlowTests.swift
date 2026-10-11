import XCTest

final class MerchantBrandImagesFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func open() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-merchant-operations-fixture"]
        app.launch(); self.app = app
        let entry = app.buttons["merchant.operations.entry.merchant.operations.profile"]
        XCTAssertTrue(revealFixtureElement(entry, in: app)); entry.tap()
        let images = app.buttons["merchant.brandImages.open"]
        XCTAssertTrue(revealFixtureElement(images, in: app)); images.tap()
        XCTAssertTrue(app.buttons["merchant.brandImages.image.0"].waitForExistence(timeout: 5)); return app
    }
    func testSavedGalleryNavigationZoomResetAndCloseLeaveEditorClean() {
        let app = open(); XCTAssertFalse(app.buttons["merchant.brandImages.image.2"].isEnabled)
        app.buttons["merchant.brandImages.image.0"].tap()
        XCTAssertTrue(app.staticTexts["merchant.brandImages.position"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["merchant.brandImages.previous"].isEnabled)
        app.buttons["merchant.brandImages.zoomIn"].tap(); XCTAssertTrue(app.buttons["merchant.brandImages.resetZoom"].isEnabled)
        app.buttons["merchant.brandImages.next"].tap(); XCTAssertFalse(app.buttons["merchant.brandImages.next"].isEnabled)
        XCTAssertFalse(app.buttons["merchant.brandImages.resetZoom"].isEnabled)
        app.buttons["merchant.brandImages.previous"].tap(); app.buttons["merchant.brandImages.back"].tap()
        XCTAssertTrue(app.buttons["merchant.brandImages.image.0"].waitForExistence(timeout: 5))
        app.buttons["merchant.brandImages.close"].tap()
        let review = app.buttons["merchant.operations.review"]; XCTAssertTrue(revealFixtureElement(review, in: app)); XCTAssertFalse(review.isEnabled)
        attachFixtureScreenshot(self, app: app, name: "Synthetic brand gallery closed without editing profile")
    }
    func testReloadReturnsToCurrentSourceListAndRepeatedOpenStartsUnzoomed() {
        let app = open(); app.buttons["merchant.brandImages.image.1"].tap(); app.buttons["merchant.brandImages.zoomIn"].tap()
        app.buttons["merchant.brandImages.reload"].tap()
        XCTAssertTrue(app.buttons["merchant.brandImages.image.0"].waitForExistence(timeout: 5))
        app.buttons["merchant.brandImages.close"].tap()
        let images = app.buttons["merchant.brandImages.open"]
        XCTAssertTrue(revealFixtureElement(images, in: app) || revealFixtureElement(images, in: app, towardTop: true)); images.tap()
        XCTAssertTrue(app.buttons["merchant.brandImages.image.0"].waitForExistence(timeout: 5)); app.buttons["merchant.brandImages.image.0"].tap()
        XCTAssertFalse(app.buttons["merchant.brandImages.resetZoom"].isEnabled)
    }
    func testBackgroundRetiresSelectedImageAndRequiresExplicitReopen() {
        let app = open(); app.buttons["merchant.brandImages.image.0"].tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertFalse(app.staticTexts["merchant.brandImages.position"].exists)
        let images = app.buttons["merchant.brandImages.open"]
        XCTAssertTrue(revealFixtureElement(images, in: app) || revealFixtureElement(images, in: app, towardTop: true)); images.tap()
        XCTAssertTrue(app.buttons["merchant.brandImages.image.0"].waitForExistence(timeout: 5))
    }
}
