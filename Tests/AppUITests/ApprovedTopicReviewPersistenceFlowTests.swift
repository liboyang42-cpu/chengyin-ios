import XCTest

/// DEBUG transport only. Real editor controls, captured review, local persistence and exact recovery are exercised.
@MainActor final class ApprovedTopicReviewPersistenceFlowTests: XCTestCase {
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
        assertProjectSubmissionEvidenceValue("projectSubmission.auditTaskID", "3301", in: app, phase: .receipt, maximumSwipes: 70, revealFirst: false); assertProjectSubmissionEvidenceValue("projectSubmission.templateIDs", "41", in: app, phase: .receipt, maximumSwipes: 70, revealFirst: false)
        tap("projectSubmission.done", in: app); tap("topicReview.open", in: app)
    }
    // UNMEASURED complete method estimate: 720 seconds. One complete journey covers actual confirmation, local receipt-write failure, explicit storage recovery, reopen and exact status read.
    func testLocalReceiptFailureRestoresOnlyThePersistedReviewRequest() throws {
        let app = launch(["--project-review-receipt-write-failure"]); submitAndOpen(in: app)
        tap("topicReview.review", in: app); tap("topicReview.confirm.submit", in: app)
        XCTAssertTrue(app.staticTexts["topicReview.unconfirmed"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["topicReview.submittedTask"].exists); let id = value("topicReview.requestID", in: app)
        tap("topicReview.close", in: app, fixed: true); tap("approvedRelease.fixture.restoreStorage", in: app, fixed: true)
        tap("projectEdit.fixture.reopen", in: app, fixed: true); tap("topicReview.open", in: app)
        value("topicReview.requestID", id, in: app); tap("topicReview.check", in: app)
        value("topicReview.submittedTask", "4402", in: app); value("topicReview.submittedVersion", "0", in: app)
        tap("topicReview.close", in: app, fixed: true); assertProjectSubmissionEvidenceValue("projectSubmission.auditTaskID", "3301", in: app, phase: .history, maximumSwipes: 70, revealFirst: false)
        let checked = try inspect(app); XCTAssertEqual(checked.reviewPrepareCount, 1); XCTAssertEqual(checked.reviewSubmitCount, 1); XCTAssertEqual(checked.reviewStatusCount, 1); XCTAssertEqual(checked.reviewTaskCount, 1); XCTAssertEqual(Set(checked.reviewRequestIDs), Set([id]))
        XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled); XCTAssertFalse(app.buttons["approvedRelease.publish"].exists)
    }
}
