import XCTest

/// Test-only server bytes pass through the ordinary editor and its actual preparation client.
@MainActor final class ApprovedReleasePreparationFlowTests: XCTestCase {
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
        value("projectSubmission.auditTaskID", "3301", in: app); value("projectSubmission.submittedState", "Pending", in: app)
        value("projectSubmission.templateIDs", "41", in: app); tap("projectSubmission.done", in: app)
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        tap("approvedRelease.read", in: app)
    }
    // UNMEASURED complete method estimate: 750 seconds. Ordinary submit, captured read, close/reopen and account invalidation are included.
    func testOrdinarySubmissionReadsCapturedServerOrderAndKeepsOriginalEvidenceAfterClose() throws {
        let app = launch(); submitAndRead(in: app)
        value("approvedRelease.name", "Synthetic server-approved title", in: app)
        value("approvedRelease.topic", "7901", in: app); value("approvedRelease.auditTask", "3301", in: app)
        value("approvedRelease.auditVersion", "2", in: app); value("approvedRelease.categories", "7,999", in: app)
        value("approvedRelease.manifestHash", String(repeating: "a", count: 64), in: app)
        value("approvedRelease.chapter.0.name", "Server-captured chapter", in: app)
        value("approvedRelease.chapter.0.block.0.text", "Server-captured story", in: app)
        value("approvedRelease.chapter.0.block.1.name", "Server-captured node", in: app)
        value("approvedRelease.chapter.0.block.1.description", "Frozen node description", in: app)
        value("approvedRelease.chapter.0.block.1.image", "Not supplied", in: app)
        value("approvedRelease.chapter.0.block.1.time", "17", in: app)
        value("approvedRelease.chapter.0.block.1.template", "73", in: app)
        value("approvedRelease.chapter.0.block.1.templateCategory", "4", in: app)
        value("approvedRelease.chapter.0.block.1.templateCategories", "7,999", in: app)
        value("approvedRelease.chapter.0.block.1.question", "Server-captured question?", in: app)
        XCTAssertFalse(app.buttons["approvedRelease.publish"].exists); XCTAssertFalse(app.buttons["projectEdit.confirmLive"].exists)
        tap("approvedRelease.close", in: app, fixed: true)
        value("projectSubmission.templateIDs", "41", in: app); value("projectSubmission.submittedState", "Pending", in: app)
        tap("projectEdit.fixture.reopen", in: app, fixed: true); tap("approvedRelease.read", in: app)
        value("approvedRelease.name", "Synthetic server-approved title", in: app); tap("approvedRelease.close", in: app, fixed: true)
        tap("projectEdit.fixture.signOut", in: app, fixed: true)
        XCTAssertFalse(app.buttons["approvedRelease.read"].exists); XCTAssertFalse(app.staticTexts["approvedRelease.name"].exists)
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
    }

}
