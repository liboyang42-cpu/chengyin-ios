import XCTest

/// Synthetic transport/result only, exercising the ordinary editor's real review and durable completion UI.
@MainActor final class ProjectSubmissionAcknowledgmentChineseFlowTests: XCTestCase {
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

    // UNMEASURED complete method estimate: 770 seconds. Both Chinese maximum-text success and partial-persistence failure launches are included.
    func testChineseLargeTextHistoricalEvidenceAndPersistenceFailureKeepTruthfulBoundaries() throws {
        var app = launch(chinese: true); assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5"); tap("projectEdit.review", in: app, fixed: true); tap("projectEdit.confirmSimulation", in: app)
        assertProjectSubmissionEvidenceValue("projectSubmission.submittedState", "待审核", in: app, phase: .receipt, maximumSwipes: 65, revealFirst: true); assertProjectSubmissionEvidenceValue("projectSubmission.auditTaskID", "3301", in: app, phase: .receipt, maximumSwipes: 65, revealFirst: true)
        assertProjectSubmissionEvidenceValue("projectSubmission.legacyVisibility", "是", in: app, phase: .receipt, maximumSwipes: 65, revealFirst: true); tap("projectSubmission.done", in: app)
        app.terminate(); app = launch(["--project-bundle-ack-write-failure"])
        tap("projectEdit.review", in: app, fixed: true); tap("projectEdit.confirmSimulation", in: app)
        XCTAssertTrue(app.buttons["projectEdit.checkOutcome"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "projectSubmission.auditTaskID").count, 0); XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        XCTAssertFalse(app.buttons["projectSubmission.done"].exists)
    }
}
