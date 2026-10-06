import XCTest

/// DEBUG server bytes only; ordinary controls and exact command persistence are exercised.
@MainActor final class ApprovedReleaseRecoveryFlowTests: XCTestCase {
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
        let target = app.buttons[id]; XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        if !fixed { XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 65), app.debugDescription) }
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(target.isEnabled && target.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(target.frame)); target.tap()
    }
    @discardableResult private func value(_ id: String, _ expected: String? = nil, in app: XCUIApplication) -> String {
        let target = app.staticTexts[id]; XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(target, in: app, maximumSwipes: 65, requiresHittable: false), app.debugDescription)
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
        value("projectSubmission.auditTaskID", "3301", in: app); value("projectSubmission.templateIDs", "41", in: app)
        tap("projectSubmission.done", in: app); tap("approvedRelease.read", in: app)
    }
    // Historical combined UNMEASURED complete method estimate: 1200 seconds. See ApprovedReleaseRecoveryMigration.json.
    // UNMEASURED complete method estimate: 900 seconds. One complete independent recovery journey; no assertions removed.
    func testChineseMaximumTextUnknownRecoveryKeepsOnlyThePersistedRequest() throws {
        let app = launch(["--project-release-publish-unknown"], chinese: true)
        assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5"); submitAndRead(in: app)
        tap("approvedRelease.publish", in: app); value("approvedRelease.confirm.name", "Synthetic server-approved title", in: app)
        tap("approvedRelease.confirm.create", in: app)
        XCTAssertTrue(app.staticTexts["approvedRelease.publication.unconfirmed"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["approvedRelease.publication.releaseID"].exists)
        let requestID = value("approvedRelease.publication.requestID", in: app)
        tap("approvedRelease.close", in: app, fixed: true); tap("projectEdit.fixture.reopen", in: app, fixed: true); tap("approvedRelease.read", in: app)
        value("approvedRelease.publication.requestID", requestID, in: app); XCTAssertFalse(app.buttons["approvedRelease.publish"].exists)
        tap("approvedRelease.publication.check", in: app)
        value("approvedRelease.publication.releaseID", "501", in: app); value("approvedRelease.publication.approval", "最近一次服务端检查时已审核通过", in: app)
        tap("approvedRelease.close", in: app, fixed: true)
        let probe = try inspect(app); XCTAssertEqual(probe.releasePublishCount, 1); XCTAssertEqual(probe.releaseStatusCount, 1); XCTAssertEqual(probe.releaseAllocatedCount, 1); XCTAssertEqual(Set(probe.releaseRequestIDs), Set([requestID]))
        app.terminate();
    }
}
