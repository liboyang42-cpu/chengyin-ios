import XCTest

/// Synthetic fixture flows; execution requires the Apple simulator pipeline.
@MainActor final class TemplateCompositionFlowTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-template-authoring", "--template-author-compound", "-AppleLanguages", "(en)"]; app.launch()
        tap("templateAuthor.begin", app); tap("templateAuthor.continue", app); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let item = app.buttons[id]
        for _ in 0..<18 { if item.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(item.waitForExistence(timeout: 3), id); XCTAssertTrue(item.isHittable, id); item.tap()
    }
    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }
    func testOpeningAndDisablingCoinKeepsDiceAndQuietEnabled() {
        let app = launch(); tap("creatorComposition.open", app); tap("templateAuthor.game.coin", app)
        let coin = app.switches["creatorComposition.enabled.coin"]; XCTAssertEqual(coin.value as? String, "1"); coin.tap(); back(app)
        tap("templateAuthor.game.dice", app); XCTAssertEqual(app.switches["creatorComposition.enabled.dice"].value as? String, "1"); back(app)
        tap("templateAuthor.game.quiet", app); XCTAssertEqual(app.switches["creatorComposition.enabled.quiet"].value as? String, "1")
    }
    func testReviewIncludesAllEnabledCompoundConfigurations() {
        let app = launch(); tap("templateAuthor.reviewPublish", app)
        for key in ["templateAuthor.game.coin", "templateAuthor.game.dice", "templateAuthor.game.quiet", "templateAuthor.timer", "creator.family.timeWindow"] {
            XCTAssertTrue(app.staticTexts["creatorComposition.review." + key].exists, key)
        }
    }
    func testLocalSaveReopenRetainsIndependentToggleChange() {
        let app = launch(); tap("creatorComposition.open", app); tap("templateAuthor.game.coin", app)
        app.switches["creatorComposition.enabled.coin"].tap(); back(app); back(app)
        tap("templateAuthor.saveLocal", app); tap("templateAuthor.fixture.reopen", app); tap("templateAuthor.restore", app)
        tap("creatorComposition.open", app); tap("templateAuthor.game.coin", app)
        XCTAssertEqual(app.switches["creatorComposition.enabled.coin"].value as? String, "0"); back(app)
        tap("templateAuthor.game.dice", app); XCTAssertEqual(app.switches["creatorComposition.enabled.dice"].value as? String, "1")
    }
}
