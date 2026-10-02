import XCTest

/// Authored for Xcode/simulator only. No UI test was run in the Linux workspace.
final class ProjectEditFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit"] + flags
        app.launch(); return app
    }
    private func find(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(element.isHittable)
    }
    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }
    func testLocalEditReviewAndCancelledConfirmation() {
        let app = launch(); let name = app.textFields["projectEdit.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); replace(name, with: "Reviewed fixture name")
        app.buttons["projectEdit.review"].tap()
        XCTAssertTrue(app.staticTexts["Reviewed fixture name"].waitForExistence(timeout: 3))
        let cancel = app.buttons["projectEdit.cancelReview"]; find(cancel, in: app); cancel.tap()
        XCTAssertTrue(app.buttons["projectEdit.review"].exists)
        XCTAssertFalse(app.staticTexts["Simulation completed. No project was published."].exists)
    }
    func testUnconfiguredReviewHasNoPublishOrSimulationAction() {
        let app = launch(["--project-edit-disabled"])
        XCTAssertTrue(app.buttons["projectEdit.review"].waitForExistence(timeout: 5)); app.buttons["projectEdit.review"].tap()
        XCTAssertFalse(app.buttons["projectEdit.confirmSimulation"].exists)
        XCTAssertTrue(app.staticTexts["Publishing is not connected. You can edit and save a local draft; nothing will be sent."].exists)
    }
    func testBlankDraftShowsValidationRatherThanFalseSuccess() {
        let app = launch(["--project-edit-blank"])
        XCTAssertTrue(app.buttons["projectEdit.review"].waitForExistence(timeout: 5)); app.buttons["projectEdit.review"].tap()
        let issue = app.staticTexts["projectEdit.issue.name"]; find(issue, in: app)
        XCTAssertTrue(issue.exists); XCTAssertFalse(app.buttons["projectEdit.confirmSimulation"].exists)
    }
    func testNewChapterRequiresStoryBeforeNodeCreation() {
        let app = launch(["--project-edit-blank"])
        XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        let add = app.buttons["projectEdit.addChapter"]; find(add, in: app); add.tap()
        let chapter = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectEdit.chapter.")).firstMatch
        find(chapter, in: app); chapter.tap()
        let addNode = app.buttons["projectEdit.addNode"]
        XCTAssertTrue(addNode.waitForExistence(timeout: 3)); XCTAssertFalse(addNode.isEnabled)
        let story = app.textFields["projectEdit.story"]
        XCTAssertTrue(story.waitForExistence(timeout: 3)); story.tap(); story.typeText("A real opening story")
        XCTAssertEqual(story.value as? String, "A real opening story")
        XCTAssertTrue(addNode.isEnabled)
    }
    func testWhitelistDisablesStructureAndScheduleButKeepsCopyEditable() {
        let app = launch(["--project-edit-whitelist"])
        XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["projectEdit.name"].isEnabled)
        let date = app.textFields["projectEdit.startDate"]; find(date, in: app); XCTAssertFalse(date.isEnabled)
        let add = app.buttons["projectEdit.addChapter"]; find(add, in: app); XCTAssertFalse(add.isEnabled)
    }
    func testLocalDraftOffersExplicitRestoreAfterReopen() {
        let app = launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        replace(app.textFields["projectEdit.name"], with: "Saved local fixture")
        app.buttons["projectEdit.saveLocal"].tap(); app.buttons["projectEdit.fixture.reopen"].tap()
        let restore = app.buttons["projectEdit.restore"]; XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.tap()
        XCTAssertEqual(app.textFields["projectEdit.name"].value as? String, "Saved local fixture")
    }
    func testUnknownOutcomeRemainsLockedAfterCheckAndReopen() {
        let app = launch(["--project-edit-unknown"])
        XCTAssertTrue(app.buttons["projectEdit.review"].waitForExistence(timeout: 5)); app.buttons["projectEdit.review"].tap()
        let confirm = app.buttons["projectEdit.confirmSimulation"]; find(confirm, in: app); confirm.tap()
        let check = app.buttons["projectEdit.checkOutcome"]; find(check, in: app); check.tap()
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        app.buttons["projectEdit.fixture.reopen"].tap()
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
    }
    func testSignOutClearsDraftAndClosesReview() {
        let app = launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        app.buttons["projectEdit.fixture.signOut"].tap()
        XCTAssertTrue(app.staticTexts["projectEdit.signIn"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.textFields["projectEdit.name"].value as? String, "Synthetic harbor trail"); XCTAssertFalse(app.buttons["projectEdit.saveLocal"].isEnabled)
    }
    func testSimulationIsExplicitlyNotPublication() {
        let app = launch(); XCTAssertTrue(app.buttons["projectEdit.review"].waitForExistence(timeout: 5)); app.buttons["projectEdit.review"].tap()
        let confirm = app.buttons["projectEdit.confirmSimulation"]; find(confirm, in: app); confirm.tap()
        let status = app.staticTexts["projectEdit.status"]; find(status, in: app)
        XCTAssertEqual(status.label, "Simulation completed. No project was published.")
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
    }
}
