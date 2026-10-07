import XCTest

/// Synthetic transport/result only, exercising the ordinary editor's real review and durable completion UI.
@MainActor final class ProjectSubmissionAcknowledgmentFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String] = [], chinese: Bool = false) -> XCUIApplication {
        let value = XCUIApplication(); app = value
        value.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "projectEdit", "--project-edit-bundle-ack"] + flags
        if chinese { value.launchArguments += ["--uitesting-max-text", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        value.launch()
        let name = value.textFields["projectEdit.name"]
        XCTAssertTrue(revealFixtureElement(name, in: value, maximumSwipes: 10), value.debugDescription)
        XCTAssertTrue(name.waitForExistence(timeout: 5)); return value
    }
    private func tap(_ id: String, in app: XCUIApplication, fixed: Bool = false) {
        let target = app.buttons[id]
        if !fixed { XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 65), app.debugDescription) }
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(target.isEnabled && target.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(target.frame)); target.tap()
    }
    private func value(_ id: String, _ expected: String, in app: XCUIApplication) {
        let target = app.staticTexts[id]
        XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 65, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(Array(target.label.utf8), Array(expected.utf8))
    }
    // UNMEASURED complete method estimate: 750 seconds. Includes submit, close, local reopen, and account invalidation.
    func testPendingPublishedFlagKeepsExactTaskThroughOrdinarySubmitAndReopen() throws {
        let app = launch(); tap("projectEdit.review", in: app, fixed: true); tap("projectEdit.confirmSimulation", in: app)
        value("projectSubmission.topicID", "7901", in: app); value("projectSubmission.auditTaskID", "3301", in: app)
        value("projectSubmission.submittedState", "Pending", in: app); value("projectSubmission.legacyVisibility", "Yes", in: app)
        value("projectSubmission.templateIDs", "41", in: app)
        XCTAssertTrue(app.staticTexts["projectSubmission.historyNotice"].exists); XCTAssertTrue(app.staticTexts["projectSubmission.releaseUnavailable"].exists)
        tap("projectSubmission.done", in: app); XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        tap("projectEdit.fixture.reopen", in: app, fixed: true)
        value("projectSubmission.auditTaskID", "3301", in: app); value("projectSubmission.submittedState", "Pending", in: app)
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled); XCTAssertFalse(app.buttons["projectEdit.confirmLive"].exists)
        tap("projectEdit.fixture.signOut", in: app, fixed: true)
        XCTAssertFalse(app.staticTexts["projectSubmission.auditTaskID"].exists); XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
    }

}
