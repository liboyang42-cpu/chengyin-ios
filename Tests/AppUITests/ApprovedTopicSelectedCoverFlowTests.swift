import XCTest

/// DEBUG transport only. Real editor controls, captured review, local persistence and exact recovery are exercised.
@MainActor final class ApprovedTopicSelectedCoverFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String] = [], chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "projectEdit", "--project-edit-bundle-ack", "--project-review-request", "--project-review-selected-cover", "--project-edit-starter-probe"] + flags
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
        value("projectSubmission.auditTaskID", "3301", in: app); value("projectSubmission.templateIDs", "41", in: app)
        tap("projectSubmission.done", in: app); tap("topicReview.open", in: app)
    }
    // UNMEASURED complete method estimate: 900 seconds. Full editor acknowledgment, exact selected-cover fields, blocked confirmation, close/reopen and zero-write probes are included.
    func testCapturedAuthorCoverRemainsExactAndNeverCreatesAReviewRequest() throws {
        let app = launch(); submitAndOpen(in:app)
        value("topicReview.selectedCover.asset","11111111-1111-4111-8111-111111111111",in:app)
        value("topicReview.selectedCover.version","22222222-2222-4222-8222-222222222222",in:app)
        value("topicReview.selectedCover.hash",String(repeating:"a",count:64),in:app)
        value("topicReview.selectedCover.selection","9",in:app); value("topicReview.selectedCover.slot","51",in:app)
        value("topicReview.cover","fixture://review-cover/reference-only",in:app)
        XCTAssertTrue(app.staticTexts["topicReview.selectedCover.blocked"].exists); XCTAssertTrue(app.staticTexts["topicReview.selectedCover.notLoaded"].exists)
        let review = app.buttons["topicReview.review"]; XCTAssertTrue(review.exists); XCTAssertFalse(review.isEnabled)
        XCTAssertFalse(app.buttons["topicReview.confirm.submit"].exists); XCTAssertFalse(app.buttons["approvedRelease.publish"].exists)
        tap("topicReview.close",in:app,fixed:true); let before = try inspect(app)
        XCTAssertEqual(before.reviewPrepareCount,1); XCTAssertEqual(before.reviewSubmitCount,0); XCTAssertEqual(before.reviewStatusCount,0); XCTAssertEqual(before.reviewTaskCount,0); XCTAssertTrue(before.reviewRequestIDs.isEmpty)
        tap("topicReview.open",in:app); value("topicReview.selectedCover.selection","9",in:app); XCTAssertFalse(app.buttons["topicReview.review"].isEnabled)
        tap("topicReview.close",in:app,fixed:true); let after = try inspect(app)
        XCTAssertEqual(after.reviewPrepareCount,2); XCTAssertEqual(after.reviewSubmitCount,0); XCTAssertEqual(after.reviewTaskCount,0); XCTAssertTrue(after.reviewRequestIDs.isEmpty)
    }
}
