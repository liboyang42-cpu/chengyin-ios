import XCTest

/// FE-STORY 7.10: the author's 「到访方式」 entry in the project editor. It shows only for a saved
/// free-exploration topic read back for its personal owner; synthetic places and server only.
final class FreeExplorationVisitConfigEntryTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ flags: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "--uitesting-module", "projectEdit", "--project-edit-visit-config"] + flags
        runningApp = app; app.launch()
        XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }
    private func entry(_ app: XCUIApplication) -> XCUIElement { app.buttons["projectEdit.visitConfig"] }
    private func assertNoEntry(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // The editor builds rows lazily, so look through the screen before concluding it is absent.
        XCTAssertFalse(revealFixtureElement(entry(app), in: app, maximumSwipes: 6), app.debugDescription, file: file, line: line)
        XCTAssertFalse(entry(app).exists, file: file, line: line)
    }

    func testAuthorOfSavedFreeExplorationTopicOpensVisitConfig() {
        let app = launch(["--project-edit-free-explore", "--project-edit-edit"])
        let link = entry(app)
        XCTAssertTrue(revealFixtureElement(link, in: app), app.debugDescription); link.tap()
        XCTAssertTrue(app.navigationBars["How visits are checked"].waitForExistence(timeout: 10), app.debugDescription)
        // The synthetic server lists the topic's places; static text is found by what is visible.
        let place = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "示例站点 A")).firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 10), app.debugDescription)
        let save = app.buttons["feVisitConfig.save.801"]
        XCTAssertTrue(revealFixtureElement(save, in: app, requiresHittable: false), app.debugDescription)
        // Writes are granted, so the read-only notice is not shown.
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "is not enabled in this build")).firstMatch.exists)
        attachFixtureScreenshot(self, app: app, name: "Author opens the visit method editor")
    }

    func testMerchantScopedTopicHasNoVisitConfigEntry() {
        assertNoEntry(launch(["--project-edit-free-explore", "--project-edit-edit", "--project-edit-merchant-owner"]))
    }

    func testUnsavedFreeExplorationDraftHasNoVisitConfigEntry() {
        assertNoEntry(launch(["--project-edit-free-explore"]))
    }

    func testCityRouteHasNoVisitConfigEntry() {
        assertNoEntry(launch(["--project-edit-edit"]))
    }
}
