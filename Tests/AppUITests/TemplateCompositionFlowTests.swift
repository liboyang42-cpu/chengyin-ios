import XCTest

/// Synthetic fixture flows; execution requires the Apple simulator pipeline.
@MainActor final class TemplateCompositionFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--ui-template-authoring", "--template-author-compound", "--template-author-toggle-probe", "-AppleLanguages", "(en)"]; app.launch()
        self.app = app
        tap("templateAuthor.begin", app); tap("templateAuthor.continue", app); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let item = app.buttons[id]
        for _ in 0..<18 { if item.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(item.waitForExistence(timeout: 3), id); XCTAssertTrue(item.isHittable, id); item.tap()
    }
    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }
    private func disableCoin(_ app: XCUIApplication) {
        let coin = app.switches["creatorComposition.enabled.coin"]
        XCTAssertTrue(coin.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(coin.value as? String, "1", app.debugDescription)
        let probe = app.buttons["creatorComposition.probe.coin"]
        let before = probe.exists ? ((probe.value as? String) ?? "unavailable") : "missing"
        tapFixtureNativeSwitch(coin, in: app)
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: coin)
        let outcome = XCTWaiter.wait(for: [disabled], timeout: 5)
        if outcome != .completed {
            // Preserve the original failure screen before reading diagnostic-only fixture state.
            // Never retry the switch or turn this failed assertion into a successful result.
            attachFixtureScreenshot(self, app: app, name: "Coin toggle before diagnostic inspection")
            var after = "probe unavailable"
            if probe.exists, revealFixtureElement(probe, in: app), probe.isEnabled {
                probe.tap(); after = (probe.value as? String) ?? "unavailable"
            }
            let attachment = XCTAttachment(string: "before: " + before + "\nafter: " + after)
            attachment.name = "Synthetic coin input dispatch and model values"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(outcome, .completed, app.debugDescription)
    }
    func testOpeningAndDisablingCoinKeepsDiceAndQuietEnabled() {
        let app = launch(); tap("creatorComposition.open", app); tap("templateAuthor.game.coin", app)
        disableCoin(app); back(app)
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
        disableCoin(app); back(app); back(app)
        tap("templateAuthor.saveLocal", app); tap("templateAuthor.fixture.reopen", app); tap("templateAuthor.restore", app)
        tap("creatorComposition.open", app); tap("templateAuthor.game.coin", app)
        XCTAssertEqual(app.switches["creatorComposition.enabled.coin"].value as? String, "0"); back(app)
        tap("templateAuthor.game.dice", app); XCTAssertEqual(app.switches["creatorComposition.enabled.dice"].value as? String, "1")
    }
}
