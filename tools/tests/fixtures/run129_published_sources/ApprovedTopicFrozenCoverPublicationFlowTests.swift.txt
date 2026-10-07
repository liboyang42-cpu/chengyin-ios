import XCTest

/// Test-only server bytes pass through the ordinary editor and its actual preparation client.
@MainActor final class ApprovedTopicFrozenCoverPublicationFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String] = [], chinese: Bool = false) -> XCUIApplication {
        let value = XCUIApplication(); app = value
        value.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "projectEdit", "--project-edit-bundle-ack", "--project-release-read", "--project-release-publish", "--project-release-publish-unknown", "--project-frozen-cover-binding"] + flags
        if chinese { value.launchArguments += ["--uitesting-max-text", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        value.launch(); XCTAssertTrue(value.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        if chinese { let app = value; assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5") }
        return value
    }
    private func tap(_ id: String, in app: XCUIApplication, fixed: Bool = false) {
        let target = app.buttons[id]; XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        if !fixed { XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 65), app.debugDescription) }
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(target.isEnabled && target.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(target.frame)); target.tap()
    }
    private func value(_ id: String, _ expected: String, in app: XCUIApplication) {
        let target = app.staticTexts[id]; XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 65, requiresHittable: false), app.debugDescription)
        XCTAssertEqual(Array(target.label.utf8), Array(expected.utf8))
    }
    private func submitAndRead(in app: XCUIApplication) {
        tap("projectEdit.review", in: app, fixed: true); tap("projectEdit.confirmSimulation", in: app)
        value("projectSubmission.auditTaskID", "3301", in: app); value("projectSubmission.submittedState", "Pending", in: app)
        value("projectSubmission.templateIDs", "41", in: app); tap("projectSubmission.done", in: app)
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        tap("approvedRelease.read", in: app)
    }
    // UNMEASURED complete method estimate: 900 seconds. Editor submission, exact approved cover confirmation, unknown allocation, close/reopen and immutable receipt recovery are included.
    func testApprovedCoverConfirmationAndUnknownPublicationRestoreOriginalManifest() throws {
        let app = launch(); submitAndRead(in: app)
        value("approvedRelease.selectedCover.asset", "11111111-1111-4111-8111-111111111111", in: app)
        value("approvedRelease.selectedCover.version", "22222222-2222-4222-8222-222222222222", in: app)
        value("approvedRelease.selectedCover.hash", String(repeating: "a", count: 64), in: app)
        XCTAssertTrue(app.staticTexts["approvedRelease.selectedCover.approvedBinding"].exists)
        tap("approvedRelease.publish", in: app)
        value("approvedRelease.confirm.selectedCover.asset", "11111111-1111-4111-8111-111111111111", in: app)
        value("approvedRelease.confirm.selectedCover.selection", "9", in: app)
        value("approvedRelease.confirm.manifestHash", String(repeating: "a", count: 64), in: app)
        tap("approvedRelease.confirm.create", in: app)
        XCTAssertTrue(app.staticTexts["approvedRelease.publication.unconfirmed"].waitForExistence(timeout: 5))
        let request = app.staticTexts["approvedRelease.publication.requestID"].label
        XCTAssertFalse(request.isEmpty)
        tap("approvedRelease.close", in: app, fixed: true); tap("projectEdit.fixture.reopen", in: app, fixed: true)
        tap("approvedRelease.read", in: app)
        value("approvedRelease.publication.requestID", request, in: app)
        value("approvedRelease.selectedCover.selection", "9", in: app)
        tap("approvedRelease.publication.check", in: app)
        value("approvedRelease.publication.releaseID", "501", in: app)
        value("approvedRelease.publication.manifestHash", String(repeating: "a", count: 64), in: app)
        XCTAssertFalse(app.buttons["approvedRelease.publication.retry"].exists)
        tap("approvedRelease.close", in: app, fixed: true)
        value("projectSubmission.auditTaskID", "3301", in: app)
        tap("projectEdit.fixture.signOut", in: app, fixed: true)
        XCTAssertFalse(app.buttons["approvedRelease.read"].exists)
        XCTAssertFalse(app.staticTexts["approvedRelease.selectedCover.asset"].exists)
    }
}
