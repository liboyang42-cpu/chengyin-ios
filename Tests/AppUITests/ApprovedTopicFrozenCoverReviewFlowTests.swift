import XCTest

/// DEBUG transport only. Real editor controls, captured review, local persistence and exact recovery are exercised.
@MainActor final class ApprovedTopicFrozenCoverReviewFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String] = [], chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "projectEdit", "--project-edit-bundle-ack", "--project-review-request", "--project-review-selected-cover", "--project-frozen-cover-binding", "--project-review-unknown", "--project-edit-starter-probe"] + flags
        if chinese { app.launchArguments += ["--uitesting-max-text", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        if chinese { assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5") }
        return app
    }
    private func tap(_ id: String, in app: XCUIApplication, fixed: Bool = false) {
        let target = app.buttons[id]
        if !fixed { XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 70), app.debugDescription) }
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(target.isEnabled && target.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(target.frame)); target.tap()
    }
    @discardableResult private func value(_ id: String, _ expected: String? = nil, in app: XCUIApplication) -> String {
        let target = app.staticTexts[id]
        XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 70, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        if let expected { XCTAssertEqual(Array(target.label.utf8), Array(expected.utf8)) }
        return target.label
    }
    private struct Probe: Decodable { let reviewPrepareCount: Int; let reviewSubmitCount: Int; let reviewStatusCount: Int; let reviewObservationCount: Int; let reviewTaskCount: Int; let reviewRequestIDs: [String] }
    private func inspect(_ app: XCUIApplication) throws -> Probe {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (app.buttons["projectStarter.fixtureSnapshot"].value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", in: app, fixed: true)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        return try JSONDecoder().decode(Probe.self, from: Data(try XCTUnwrap(probe.value as? String).utf8))
    }
    private func submitAndOpen(in app: XCUIApplication) {
        tap("projectEdit.review", in: app, fixed: true); tap("projectEdit.confirmSimulation", in: app)
        assertProjectSubmissionEvidenceValue("projectSubmission.auditTaskID", "3301", in: app, phase: .receipt, maximumSwipes: 70, revealFirst: true); assertProjectSubmissionEvidenceValue("projectSubmission.templateIDs", "41", in: app, phase: .receipt, maximumSwipes: 70, revealFirst: true)
        tap("projectSubmission.done", in: app); tap("topicReview.open", in: app)
    }
    // UNMEASURED complete method estimate: 900 seconds. Ordinary editor receipt, exact bound cover, cancel, unknown submission and original-request recovery are included.
    func testBoundCoverReviewConfirmCancelAndUnknownRecoveryKeepOneExactRequest() throws {
        let app = launch(); submitAndOpen(in: app)
        value("topicReview.selectedCover.asset", "11111111-1111-4111-8111-111111111111", in: app)
        value("topicReview.selectedCover.hash", String(repeating: "a", count: 64), in: app)
        value("topicReview.selectedCover.selection", "9", in: app)
        XCTAssertTrue(app.staticTexts["topicReview.selectedCover.reviewBinding"].exists)
        XCTAssertFalse(app.staticTexts["topicReview.selectedCover.blocked"].exists)
        tap("topicReview.review", in: app)
        value("topicReview.confirm.selectedCover.asset", "11111111-1111-4111-8111-111111111111", in: app)
        value("topicReview.confirm.selectedCover.selection", "9", in: app)
        tap("topicReview.confirm.cancel", in: app, fixed: true)
        tap("topicReview.close", in: app, fixed: true)
        XCTAssertEqual(try inspect(app).reviewSubmitCount, 0)
        tap("topicReview.open", in: app); tap("topicReview.review", in: app); tap("topicReview.confirm.submit", in: app)
        XCTAssertTrue(app.staticTexts["topicReview.unconfirmed"].waitForExistence(timeout: 5))
        let request = value("topicReview.requestID", in: app)
        tap("topicReview.close", in: app, fixed: true); tap("topicReview.open", in: app)
        value("topicReview.requestID", request, in: app); tap("topicReview.check", in: app)
        value("topicReview.submittedTask", "4402", in: app); value("topicReview.submittedState", "Pending review", in: app)
        value("topicReview.requestID", request, in: app); XCTAssertFalse(app.buttons["topicReview.confirm.submit"].exists)
        tap("topicReview.close", in: app, fixed: true); let saved = try inspect(app)
        XCTAssertEqual(saved.reviewSubmitCount, 1); XCTAssertEqual(saved.reviewStatusCount, 1); XCTAssertEqual(saved.reviewTaskCount, 1)
        XCTAssertEqual(Set(saved.reviewRequestIDs), [request])
    }
}
