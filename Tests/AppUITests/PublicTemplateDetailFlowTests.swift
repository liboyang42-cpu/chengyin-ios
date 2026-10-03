import XCTest

final class PublicTemplateDetailFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ options: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "publicTemplateDetail", "-AppleLanguages", "(\(language))", "-AppleLocale", language] + options
        app.launch(); return app
    }
    func testPublicContentHasNoAdoptionOrRecruitmentForGuest() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["A neighborhood in three chapters"].waitForExistence(timeout: 5))
        let total = app.staticTexts["discovery.publicTotalStops"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertEqual(total.label, "Total route stops, 6", "Public preview rows must not replace the authoritative total")
        XCTAssertFalse(app.buttons["templateAuthor.adopt"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["discovery.publicRecruitment"].exists)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["The first corner"], in: app))
        XCTAssertTrue(app.staticTexts["The first corner"].exists)
    }
    func testMerchantProjectionClearsImmediatelyOnContextChange() {
        let app = launch(["--public-template-merchant"])
        XCTAssertTrue(app.staticTexts["A neighborhood in three chapters"].waitForExistence(timeout: 5))
        let recruitment = app.descendants(matching: .any)["discovery.publicRecruitment"].firstMatch
        XCTAssertTrue(revealFixtureElement(recruitment, in: app))
        app.buttons["discovery.publicFixture.invalidate"].tap()
        XCTAssertTrue(app.staticTexts["Your account context changed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["A neighborhood in three chapters"].exists)
        XCTAssertFalse(recruitment.exists)
    }
    func testEmptyProjectionAndChineseContent() {
        let app = launch(["--public-template-empty"], language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["暂无公开章节或玩法。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["templateAuthor.adopt"].exists)
    }
    func testLoadingCanBeInvalidatedBeforeCompletion() {
        let app = launch(["--public-template-loading"])
        XCTAssertTrue(app.buttons["discovery.publicFixture.invalidate"].waitForExistence(timeout: 5))
        app.buttons["discovery.publicFixture.invalidate"].tap()
        XCTAssertTrue(app.staticTexts["Your account context changed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["A neighborhood in three chapters"].exists)
    }
    func testReadFailureDoesNotLeaveShelfContentInDetail() {
        let app = launch(["--public-template-error"])
        XCTAssertTrue(app.buttons["discovery.retry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["A neighborhood in three chapters"].exists)
    }
}
