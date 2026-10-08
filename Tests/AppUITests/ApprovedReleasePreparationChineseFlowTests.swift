import XCTest

/// Test-only server bytes pass through the ordinary editor and its actual preparation client.
@MainActor final class ApprovedReleasePreparationChineseFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String] = [], chinese: Bool = false) -> XCUIApplication {
        let value = XCUIApplication(); app = value
        value.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "projectEdit", "--project-edit-bundle-ack", "--project-release-read"] + flags
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
    private func submitAndRead(in app: XCUIApplication) {
        tap("projectEdit.review", in: app, fixed: true); tap("projectEdit.confirmSimulation", in: app)
        assertProjectSubmissionEvidenceValue("projectSubmission.auditTaskID", "3301", in: app, phase: .receipt, maximumSwipes: 65, revealFirst: true); assertProjectSubmissionEvidenceValue("projectSubmission.submittedState", "Pending", in: app, phase: .receipt, maximumSwipes: 65, revealFirst: true)
        assertProjectSubmissionEvidenceValue("projectSubmission.templateIDs", "41", in: app, phase: .receipt, maximumSwipes: 65, revealFirst: true); tap("projectSubmission.done", in: app)
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        tap("approvedRelease.read", in: app)
    }

    // UNMEASURED complete method estimate: 750 seconds. Chinese maximum-text submit, changed-review failure, retry and close are included.
    func testChineseMaximumTextCurrentReviewFailureCanRetryWithoutCallingItPublished() throws {
        let app = launch(["--project-release-changed-once"], chinese: true)
        assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")
        tap("projectEdit.review", in: app, fixed: true); tap("projectEdit.confirmSimulation", in: app)
        assertProjectSubmissionEvidenceValue("projectSubmission.submittedState", "待审核", in: app, phase: .receipt, maximumSwipes: 65, revealFirst: true); tap("projectSubmission.done", in: app)
        tap("approvedRelease.read", in: app)
        XCTAssertTrue(app.staticTexts["approvedRelease.failed"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["approvedRelease.name"].exists); XCTAssertFalse(app.buttons["approvedRelease.publish"].exists)
        tap("approvedRelease.retry", in: app)
        value("approvedRelease.name", "Synthetic server-approved title", in: app)
        value("approvedRelease.description", "未提供", in: app)
        value("approvedRelease.auditVersion", "2", in: app)
        value("approvedRelease.chapter.0.block.0.text", "Server-captured story", in: app)
        value("approvedRelease.chapter.0.block.1.template", "73", in: app)
        value("approvedRelease.chapter.0.block.1.templateCategory", "4", in: app)
        value("approvedRelease.chapter.0.block.1.templateCategories", "7,999", in: app)
        tap("approvedRelease.close", in: app, fixed: true)
        assertProjectSubmissionEvidenceValue("projectSubmission.submittedState", "待审核", in: app, phase: .history, maximumSwipes: 65, revealFirst: true)
        assertProjectSubmissionEvidenceValue("projectSubmission.legacyVisibility", "是", in: app, phase: .history, maximumSwipes: 65, revealFirst: true)
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled); XCTAssertFalse(app.buttons["projectEdit.confirmLive"].exists)
    }
}
