import XCTest

/// Full owned-list → real topic detail → professional editor routes with offline HTTP bytes.
/// No UI method has run on Apple tooling for this packet.
@MainActor final class ProjectOwnedEditorFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        app?.terminate(); let value = XCUIApplication(); app = value
        value.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-owned-flow"] + flags
        value.launch(); return value
    }
    private func tap(_ id: String, in app: XCUIApplication, fixed: Bool = false) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        if !fixed { XCTAssertTrue(revealFixtureElement(button, in: app, maximumSwipes: 50), app.debugDescription) }
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(button.isEnabled && button.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame)); button.tap()
    }
    private func back(_ app: XCUIApplication) {
        let values = app.navigationBars.buttons.matching(identifier: "BackButton").allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(values.count, 1); guard values.count == 1 else { return }; values[0].tap()
    }
    private func openEditor(_ app: XCUIApplication) {
        tap("creatorContent.project.topic:71", in: app)
        XCTAssertTrue(app.staticTexts["Synthetic route"].waitForExistence(timeout: 5))
        tap("projectRemote.edit", in: app, fixed: true)
    }
    private func assertMode(_ mode: String, in app: XCUIApplication) {
        let value = app.staticTexts["projectRemote.mode"]
        XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertEqual(value.label, mode)
        let version = app.staticTexts["projectRemote.version.value"]
        XCTAssertTrue(version.exists, app.debugDescription)
        XCTAssertEqual(Array(version.label.utf8), Array("fixture-r2".utf8))
    }
    // UNMEASURED complete method estimate: 480 seconds.
    func testCityOwnedDetailReadsStoryAndPreparedNodeWithoutInferringPublication() throws {
        let app = launch(["--project-owned-city"]); openEditor(app); assertMode("City orientation", in: app)
        tap("projectEdit.chapter.chapter-11", in: app)
        XCTAssertTrue(app.textFields["projectEdit.chapterName"].waitForExistence(timeout: 5))
        back(app); tap("projectEdit.review", in: app, fixed: true)
        let template = app.staticTexts["projectPrepared.chapter.0.node.0.templateId"]
        XCTAssertTrue(revealFixtureElement(template, in: app, maximumSwipes: 60, requiresHittable: false)); XCTAssertEqual(template.label, "73")
        XCTAssertFalse(app.buttons["projectEdit.confirmLive"].exists); XCTAssertFalse(app.buttons["projectEdit.confirmSimulation"].exists)
        tap("projectEdit.cancelReview", in: app)
        tap("projectOwned.fixture.signOut", in: app, fixed: true)
        XCTAssertTrue(app.staticTexts["creatorContent.issue"].waitForExistence(timeout: 5)); XCTAssertFalse(app.textFields["projectEdit.name"].exists)
    }
    // UNMEASURED complete method estimate: 720 seconds. Both launches are included.
    func testFreeOwnedEditBackRestoreAndExplicitCompletedContinuation() throws {
        var app = launch(); openEditor(app); assertMode("Free exploration", in: app)
        let name = app.textFields["projectEdit.name"]
        XCTAssertTrue(revealFixtureElement(name, in: app, maximumSwipes: 40)); let old = try XCTUnwrap(name.value as? String)
        name.tap(); name.typeText(" local"); let edited = try XCTUnwrap(name.value as? String)
        XCTAssertNotEqual(edited, old); XCTAssertTrue(edited.contains(" local"))
        tap("projectEdit.saveLocal", in: app, fixed: true); back(app)
        tap("projectRemote.edit", in: app, fixed: true)
        tap("projectEdit.restore", in: app)
        XCTAssertTrue(revealFixtureElement(app.textFields["projectEdit.name"], in: app, maximumSwipes: 40))
        XCTAssertEqual(Array(try XCTUnwrap(app.textFields["projectEdit.name"].value as? String).utf8), Array(edited.utf8))
        back(app); back(app); XCTAssertTrue(app.buttons["creatorContent.project.topic:71"].waitForExistence(timeout: 5))
        app = launch(["--project-owned-completed"]); openEditor(app)
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        tap("projectRemote.continue", in: app)
        XCTAssertTrue(app.buttons["projectEdit.review"].isEnabled); assertMode("Free exploration", in: app)
        XCTAssertFalse(app.buttons["projectRemote.continue"].exists)
    }
    // UNMEASURED complete method estimate: 240 seconds.
    func testDeniedEditKeepsPublicDetailAndNeverExposesEditableDraft() {
        let app = launch(["--project-owned-denied"]); openEditor(app)
        XCTAssertTrue(app.buttons["projectEdit.reload"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["projectEdit.name"].exists); XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        tap("projectEdit.reload", in: app)
        XCTAssertFalse(app.textFields["projectEdit.name"].exists); back(app)
        XCTAssertTrue(app.staticTexts["Synthetic route"].waitForExistence(timeout: 5)); back(app)
        XCTAssertTrue(app.buttons["creatorContent.project.topic:71"].waitForExistence(timeout: 5))
    }
}
