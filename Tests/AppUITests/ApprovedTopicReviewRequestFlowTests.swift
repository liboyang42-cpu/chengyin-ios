import XCTest

/// DEBUG transport only. Real editor controls, captured review, local persistence and exact recovery are exercised.
@MainActor final class ApprovedTopicReviewRequestFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String] = [], chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "projectEdit", "--project-edit-bundle-ack", "--project-review-request", "--project-edit-starter-probe"] + flags
        if chinese { app.launchArguments += ["--uitesting-max-text", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        if chinese { assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5") }
        return app
    }
    private func tap(_ id: String, in app: XCUIApplication, fixed: Bool = false) {
        let target = app.buttons[id]; XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        if !fixed { XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 70), app.debugDescription) }
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(target.isEnabled && target.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(target.frame)); target.tap()
    }
    @discardableResult private func value(_ id: String, _ expected: String? = nil, in app: XCUIApplication) -> String {
        let target = app.staticTexts[id]; XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 70, requiresHittable: false), app.debugDescription)
        if let expected { XCTAssertEqual(Array(target.label.utf8), Array(expected.utf8)) }
        return target.label
    }
    private struct Probe: Decodable { let reviewPrepareCount: Int; let reviewSubmitCount: Int; let reviewStatusCount: Int; let reviewTaskCount: Int; let reviewRequestIDs: [String] }
    private func inspect(_ app: XCUIApplication) throws -> Probe {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (app.buttons["projectStarter.fixtureSnapshot"].value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", in: app, fixed: true)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        return try JSONDecoder().decode(Probe.self, from: Data(try XCTUnwrap(probe.value as? String).utf8))
    }
    private func submitAndOpen(in app: XCUIApplication) {
        tap("projectEdit.review", in: app, fixed: true); tap("projectEdit.confirmSimulation", in: app)
        value("projectSubmission.auditTaskID", "3301", in: app); value("projectSubmission.templateIDs", "41", in: app)
        tap("projectSubmission.done", in: app); tap("topicReview.open", in: app)
    }
    // UNMEASURED complete method estimate: 720 seconds. One launch covers original submission, exact captured content, cancel, explicit request, historical receipt and account invalidation.
    func testCapturedReviewRequestKeepsOriginalReceiptAndCancelCannotSubmit() throws {
        let app = launch(); submitAndOpen(in: app)
        value("topicReview.name", "Test-only current review capture", in: app)
        value("topicReview.observedTask", "3301", in: app); value("topicReview.cover", "fixture://review-cover/reference-only", in: app)
        value("topicReview.chapter.0.block.0.text", "Test-only captured story", in: app)
        value("topicReview.chapter.0.block.1.template", "73", in: app)
        value("topicReview.chapter.0.block.1.templateCategory", "4", in: app)
        tap("topicReview.review", in: app); value("topicReview.confirm.name", "Test-only current review capture", in: app)
        tap("topicReview.confirm.cancel", in: app, fixed: true); tap("topicReview.close", in: app, fixed: true)
        let cancelled = try inspect(app); XCTAssertEqual(cancelled.reviewSubmitCount, 0); XCTAssertEqual(cancelled.reviewTaskCount, 0)
        tap("topicReview.open", in: app); tap("topicReview.review", in: app)
        value("topicReview.confirm.snapshotHash", String(repeating: "c", count: 64), in: app); tap("topicReview.confirm.submit", in: app)
        value("topicReview.submittedTask", "4402", in: app); value("topicReview.submittedState", "Pending review", in: app)
        let id = value("topicReview.requestID", in: app); XCTAssertNotNil(UUID(uuidString: id)); XCTAssertFalse(app.buttons["approvedRelease.publish"].exists)
        tap("topicReview.close", in: app, fixed: true)
        value("projectSubmission.auditTaskID", "3301", in: app); value("projectSubmission.submittedState", "Pending", in: app)
        let sent = try inspect(app); XCTAssertEqual(sent.reviewSubmitCount, 1); XCTAssertEqual(sent.reviewTaskCount, 1); XCTAssertEqual(sent.reviewRequestIDs, [id])
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        tap("projectEdit.fixture.signOut", in: app, fixed: true); XCTAssertFalse(app.buttons["topicReview.open"].exists); XCTAssertFalse(app.staticTexts["topicReview.submittedTask"].exists)
    }
}
