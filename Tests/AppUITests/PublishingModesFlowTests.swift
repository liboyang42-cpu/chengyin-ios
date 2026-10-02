import XCTest

/// Authored, NOT_RUN. Integrator must mount PublishingModesFixtureHost for this flag.
@MainActor final class PublishingModesFlowTests: XCTestCase {
    private func launch(_ language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-publishing-modes", "-AppleLanguages", "(\(language))"]; app.launch(); return app
    }
    func testQuickDraftCannotSkipPlaceConfirmation() {
        let app = launch(); app.buttons["Quick route setup"].tap()
        app.buttons["publishModes.quick.continue"].tap()
        XCTAssertTrue(app.staticTexts["Add a title and at least one named stop, then confirm every location."].exists)
        XCTAssertFalse(app.staticTexts["publishModes.fixture.seed"].exists)
    }
    func testActivityIsDistinctFromQuickRoute() {
        let app = launch(); app.buttons["Publish an activity"].tap()
        XCTAssertTrue(app.textFields["publishModes.activity.start"].exists)
        XCTAssertFalse(app.buttons["publishModes.quick.continue"].exists)
        app.buttons["publishModes.activity.review"].tap()
        XCTAssertTrue(app.staticTexts["publishModes.message"].exists)
    }
    func testIdentityNeverCollectsSensitiveID() {
        let app = launch(); app.buttons["Publisher registration"].tap()
        XCTAssertEqual(app.secureTextFields.count, 0); XCTAssertEqual(app.textFields.count, 0)
    }
    func testChineseEntryIsLocalized() {
        let app = launch("zh-Hans"); XCTAssertTrue(app.buttons["快速配置"].exists); XCTAssertTrue(app.buttons["发布活动"].exists)
    }
}
