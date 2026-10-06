import XCTest

/// DEBUG transport only. Real editor controls, captured review, local persistence and exact recovery are exercised.
@MainActor final class ApprovedTopicReviewCurrentFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String] = [], chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "projectEdit", "--project-edit-bundle-ack", "--project-review-request", "--project-review-current", "--project-edit-starter-probe"] + flags
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
        value("projectSubmission.auditTaskID", "3301", in: app); value("projectSubmission.templateIDs", "41", in: app)
        tap("projectSubmission.done", in: app); tap("topicReview.open", in: app)
    }
    // UNMEASURED complete method estimate: 900 seconds. Full ordinary fixture submission, captured request, two explicit current reads, close/reopen, changed server task state and original receipts are included.
    func testExplicitCurrentTaskReadUpdatesObservationWithoutChangingEitherHistoricalReceipt() throws {
        let app = launch(); submitAndOpen(in:app)
        tap("topicReview.review",in:app); tap("topicReview.confirm.submit",in:app)
        value("topicReview.submittedTask","4402",in:app); value("topicReview.submittedState","Pending review",in:app)
        let request = value("topicReview.requestID",in:app); XCTAssertFalse(app.staticTexts["topicReview.current.state"].exists)
        tap("topicReview.current.read",in:app); value("topicReview.current.task","4402",in:app); value("topicReview.current.version","0",in:app)
        value("topicReview.current.state","Pending review",in:app); value("topicReview.current.hash",String(repeating:"c",count:64),in:app)
        value("topicReview.current.captureMatch","This task still references your submitted capture.",in:app)
        XCTAssertTrue(app.staticTexts["topicReview.current.notice"].exists); XCTAssertFalse(app.buttons["approvedRelease.publish"].exists)
        tap("topicReview.close",in:app,fixed:true); tap("topicReview.fixture.simulateApproval",in:app,fixed:true); tap("topicReview.open",in:app)
        XCTAssertFalse(app.staticTexts["topicReview.current.state"].exists); tap("topicReview.current.read",in:app)
        value("topicReview.current.state","Review task approved",in:app); value("topicReview.current.version","1",in:app)
        value("topicReview.submittedState","Pending review",in:app); value("topicReview.requestID",request,in:app)
        XCTAssertFalse(app.buttons["approvedRelease.publish"].exists); tap("topicReview.close",in:app,fixed:true)
        value("projectSubmission.auditTaskID","3301",in:app); value("projectSubmission.submittedState","Pending",in:app)
        let checked = try inspect(app); XCTAssertEqual(checked.reviewPrepareCount,1); XCTAssertEqual(checked.reviewSubmitCount,1); XCTAssertEqual(checked.reviewStatusCount,0); XCTAssertEqual(checked.reviewObservationCount,2); XCTAssertEqual(checked.reviewTaskCount,1); XCTAssertEqual(Set(checked.reviewRequestIDs),Set([request]))
    }
}
