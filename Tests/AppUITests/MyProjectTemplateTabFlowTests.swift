import XCTest

/// Offline fixture only: mini myproject's template tab must not reuse `api/project/my` rows.
final class MyProjectTemplateTabFlowTests: XCTestCase {
    func testTemplateTypeShowsOwnShelfStateInsteadOfProjectRows() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "creatorContent"]
        app.launch(); app.buttons["creatorContent.openProjects"].tap()
        XCTAssertTrue(app.buttons["creatorContent.project.topic:301"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Content type")).firstMatch.tap()
        app.buttons["Templates"].tap()
        // The fixture host injects no shelf, so the explicit unavailable state is shown.
        XCTAssertTrue(app.staticTexts["myProject.template.unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["creatorContent.project.topic:301"].exists)
    }
}
