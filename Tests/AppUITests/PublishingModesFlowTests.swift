import XCTest

/// Authored, NOT_RUN. Integrator must mount PublishingModesFixtureHost for this flag.
@MainActor final class PublishingModesFlowTests: XCTestCase {
    private func launch(_ language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--ui-publishing-modes", "-AppleLanguages", "(\(language))"]; app.launch(); return app
    }
    func testQuickDraftCannotSkipPlaceConfirmation() {
        let app = launch(); app.buttons["Quick route setup"].tap()
        app.buttons["publishModes.quick.continue"].tap()
        XCTAssertTrue(app.staticTexts["Add a title and at least one named stop, then confirm every location."].exists)
        XCTAssertFalse(app.staticTexts["publishModes.fixture.seed"].exists)
    }
    func testActivityIsDistinctFromQuickRoute() {
        let app = launch(); app.buttons["Publish an activity"].tap()
        XCTAssertTrue(app.textFields["publishModes.activity.start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["publishModes.quick.continue"].exists)
        // Activity review follows the category, template, collaborator and local-draft
        // sections. The Form does not materialize this button in its initial viewport.
        let review = app.buttons["publishModes.activity.review"]
        for _ in 0..<8 { if review.exists && review.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(review.exists, app.debugDescription)
        XCTAssertTrue(review.isHittable, app.debugDescription)
        XCTAssertTrue(review.isEnabled); review.tap()
        let message = app.staticTexts["publishModes.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(message.label, "Check the required fields, event times and ticket windows. Publishing also requires a current club-leader role.")
        XCTAssertFalse(app.buttons["publishModes.quick.continue"].exists)
        XCTAssertFalse(app.staticTexts["publishModes.fixture.seed"].exists)
    }
    func testIdentityNeverCollectsSensitiveID() {
        let app = launch(); app.buttons["Publisher registration"].tap()
        XCTAssertEqual(app.secureTextFields.count, 0); XCTAssertEqual(app.textFields.count, 0)
    }
    func testChineseEntryIsLocalized() {
        let app = launch("zh-Hans"); XCTAssertTrue(app.buttons["快速配置"].exists); XCTAssertTrue(app.buttons["发布活动"].exists)
    }
}
