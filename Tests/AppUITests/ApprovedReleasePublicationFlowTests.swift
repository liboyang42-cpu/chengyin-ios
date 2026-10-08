import XCTest

/// DEBUG server bytes only; ordinary controls and exact command persistence are exercised.
@MainActor final class ApprovedReleasePublicationFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String] = [], chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "projectEdit", "--project-edit-bundle-ack", "--project-release-read", "--project-release-publish", "--project-edit-starter-probe"] + flags
        if chinese { app.launchArguments += ["--uitesting-max-text", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        if chinese { assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5") }
        return app
    }
    private func tap(_ id: String, in app: XCUIApplication, fixed: Bool = false) {
        let target = app.buttons[id]
        if !fixed { XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 65), app.debugDescription) }
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(target.isEnabled && target.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(target.frame)); target.tap()
    }
    @discardableResult private func value(_ id: String, _ expected: String? = nil, in app: XCUIApplication) -> String {
        let target = app.staticTexts[id]
        XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 65, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        if let expected { XCTAssertEqual(Array(target.label.utf8), Array(expected.utf8)) }
        return target.label
    }
    private struct Probe: Decodable { let releasePublishCount: Int; let releaseStatusCount: Int; let releaseAllocatedCount: Int; let releaseRequestIDs: [String] }
    private func inspect(_ app: XCUIApplication) throws -> Probe {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (app.buttons["projectStarter.fixtureSnapshot"].value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", in: app, fixed: true)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        return try JSONDecoder().decode(Probe.self, from: Data(try XCTUnwrap(probe.value as? String).utf8))
    }
    private func submitAndRead(in app: XCUIApplication) {
        tap("projectEdit.review", in: app, fixed: true); tap("projectEdit.confirmSimulation", in: app)
        assertProjectSubmissionEvidenceValue("projectSubmission.auditTaskID", "3301", in: app, phase: .receipt, maximumSwipes: 65, revealFirst: true); assertProjectSubmissionEvidenceValue("projectSubmission.templateIDs", "41", in: app, phase: .receipt, maximumSwipes: 65, revealFirst: true)
        tap("projectSubmission.done", in: app); tap("approvedRelease.read", in: app)
    }
    // UNMEASURED complete method estimate: 900 seconds. Includes normal submit/read, cancel, captured confirmation, local reopen and account invalidation.
    func testCapturedConfirmationCreatesOneImmutableReceiptAndReopensWithoutAnotherPublish() throws {
        let app = launch(); submitAndRead(in: app)
        tap("approvedRelease.publish", in: app)
        value("approvedRelease.confirm.name", "Synthetic server-approved title", in: app)
        value("approvedRelease.confirm.headRevision", "0", in: app)
        value("approvedRelease.confirm.chapter.0.block.1.template", "73", in: app)
        value("approvedRelease.confirm.chapter.0.block.1.templateCategory", "4", in: app)
        value("approvedRelease.confirm.chapter.0.block.1.templateCategories", "7,999", in: app)
        tap("approvedRelease.confirm.cancel", in: app, fixed: true)
        XCTAssertFalse(app.staticTexts["approvedRelease.publication.releaseID"].exists)
        tap("approvedRelease.close", in: app, fixed: true)
        let cancelled = try inspect(app); XCTAssertEqual(cancelled.releasePublishCount, 0); XCTAssertEqual(cancelled.releaseAllocatedCount, 0)
        tap("approvedRelease.read", in: app); tap("approvedRelease.publish", in: app)
        value("approvedRelease.confirm.manifestHash", String(repeating: "a", count: 64), in: app)
        tap("approvedRelease.confirm.create", in: app)
        value("approvedRelease.publication.releaseID", "501", in: app)
        value("approvedRelease.publication.manifestHash", String(repeating: "a", count: 64), in: app)
        let requestID = value("approvedRelease.publication.requestID", in: app); XCTAssertNotNil(UUID(uuidString: requestID))
        XCTAssertFalse(app.buttons["approvedRelease.publish"].exists)
        tap("approvedRelease.close", in: app, fixed: true)
        assertProjectSubmissionEvidenceValue("projectSubmission.submittedState", "Pending", in: app, phase: .history, maximumSwipes: 65, revealFirst: true); XCTAssertFalse(app.buttons["projectEdit.review"].isEnabled)
        let published = try inspect(app); XCTAssertEqual(published.releasePublishCount, 1); XCTAssertEqual(published.releaseAllocatedCount, 1); XCTAssertEqual(published.releaseRequestIDs, [requestID])
        tap("projectEdit.fixture.reopen", in: app, fixed: true); tap("approvedRelease.read", in: app)
        value("approvedRelease.publication.releaseID", "501", in: app)
        value("approvedRelease.publication.requestID", requestID, in: app)
        tap("approvedRelease.publication.check", in: app)
        value("approvedRelease.publication.releaseID", "501", in: app); tap("approvedRelease.close", in: app, fixed: true)
        let checked = try inspect(app); XCTAssertEqual(checked.releasePublishCount, 1); XCTAssertEqual(checked.releaseStatusCount, 1); XCTAssertEqual(Set(checked.releaseRequestIDs), Set([requestID]))
        tap("projectEdit.fixture.signOut", in: app, fixed: true)
        XCTAssertFalse(app.buttons["approvedRelease.read"].exists); XCTAssertFalse(app.staticTexts["approvedRelease.publication.releaseID"].exists)
    }
}
