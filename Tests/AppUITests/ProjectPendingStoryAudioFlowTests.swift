import XCTest

/// Synthetic actual pending-host actions; no provider, user file or live network.
@MainActor final class ProjectPendingStoryAudioFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func tap(_ id: String, _ app: XCUIApplication, fixed: Bool = false) {
        let button = app.buttons[id]
        if !fixed { XCTAssertTrue(revealFixtureElement(button, in: app, maximumSwipes: 45), app.debugDescription) }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame)); button.tap()
    }
    private func snapshot(_ app: XCUIApplication) throws -> [String: Any] {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (probe.value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", app, fixed: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)], timeout: 5), .completed)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(probe.value as? String).utf8)) as? [String: Any])
        XCTAssertEqual(value["submissionCount"] as? Int, 0)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        return value
    }
    private func chapter(_ snapshot: [String: Any]) throws -> [String: Any] {
        let draft = try XCTUnwrap(snapshot["savedDraft"] as? [String: Any])
        return try XCTUnwrap((draft["chapters"] as? [[String: Any]])?.first)
    }
    private func blocks(_ snapshot: [String: Any]) throws -> [[String: Any]] { try XCTUnwrap(chapter(snapshot)["blocks"] as? [[String: Any]]) }
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); button.tap()
    }
    private func reference(_ app: XCUIApplication, _ expected: String) {
        let value = app.staticTexts["projectStoryAudio.reference"]
        XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertEqual(Array(value.label.utf8), Array(expected.utf8))
    }
    private func material(_ snapshot: [String: Any]) throws -> String {
        let draft = try XCTUnwrap(snapshot["savedDraft"] as? [String: Any])
        let material = try XCTUnwrap((draft["pendingMaterials"] as? [[String: Any]])?.first)
        return try XCTUnwrap((material["node"] as? [String: Any])?["id"] as? String)
    }
    private func pendingCount(_ snapshot: [String: Any]) throws -> Int {
        let draft = try XCTUnwrap(snapshot["savedDraft"] as? [String: Any])
        return (draft["pendingMaterials"] as? [Any])?.count ?? 0
    }
    private func chooseChapter(_ app: XCUIApplication, materialID: String, name: String) {
        tap("projectPending.arrange." + materialID, app)
        let choices = app.buttons.matching(NSPredicate(format: "label == %@", name)).allElementsBoundByIndex.filter { $0.isEnabled && $0.isHittable }
        XCTAssertEqual(choices.count, 1); guard choices.count == 1 else { return }
        XCTAssertTrue(app.windows.firstMatch.frame.contains(choices[0].frame)); choices[0].tap()
    }
    // UNMEASURED complete-method estimate: 900 seconds. Existing pending story, audio cancel/apply, explicit placement, prepared order and restore.
    func testPendingExistingStoryAudioSavesBeforeExplicitMaterialInsertionAndPreparedReview() throws {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-edit-starter-probe", "--project-edit-pending", "--project-story-image", "--project-story-audio"]
        app.launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5)); assertFixtureEnvironment(in: app, dynamicTypeSize: "large")
        tap("projectEdit.saveLocal", app, fixed: true); var saved = try snapshot(app)
        let materialID = try material(saved), name = try XCTUnwrap(chapter(saved)["name"] as? String)
        chooseChapter(app, materialID: materialID, name: name); tap("projectStoryAudio.add", app)
        tap("projectPending.close", app, fixed: true); saved = try snapshot(app)
        let blockID = try XCTUnwrap(blocks(saved).last?["id"] as? String)
        XCTAssertEqual(try blocks(saved).last?["url"] as? String, ""); XCTAssertEqual(try pendingCount(saved), 1)
        chooseChapter(app, materialID: materialID, name: name); tap("projectStoryAudio.open." + blockID, app)
        tap("projectStoryAudio.choose", app); XCTAssertTrue(app.staticTexts["projectStoryAudio.notUploaded"].exists)
        tap("projectStoryAudio.cancelLocal", app); XCTAssertFalse(app.buttons["projectStoryAudio.upload"].exists)
        tap("projectStoryAudio.choose", app); tap("projectStoryAudio.upload", app)
        let exact = "https://example.com/synthetic/story/e%CC%81.m4a?version=1"
        reference(app, exact); tap("projectStoryAudio.apply", app)
        XCTAssertFalse(app.buttons["projectStoryAudio.close"].exists); XCTAssertTrue(app.buttons["projectPending.close"].exists)
        tap("projectPending.insert.end", app); XCTAssertFalse(app.buttons["projectPending.close"].exists)
        saved = try snapshot(app); XCTAssertEqual(try pendingCount(saved), 0)
        XCTAssertEqual(saved["storyAudioUploadCount"] as? Int, 1); XCTAssertEqual(saved["storyImageUploadCount"] as? Int, 0)
        let rows = try blocks(saved); XCTAssertEqual(rows.map { $0["kind"] as? String }, ["text", "node", "audio", "node"])
        XCTAssertEqual(rows[2]["id"] as? String, blockID); XCTAssertEqual(Array(try XCTUnwrap(rows[2]["url"] as? String).utf8), Array(exact.utf8))
        XCTAssertEqual(rows[3]["nodeID"] as? String, materialID)
        tap("projectEdit.review", app, fixed: true); let prepared = app.staticTexts["projectStoryAudio.prepared.0.2"]
        XCTAssertTrue(revealFixtureElement(prepared, in: app, maximumSwipes: 45, requiresHittable: false)); XCTAssertEqual(Array(prepared.label.utf8), Array(exact.utf8))
        tap("projectEdit.cancelReview", app); tap("projectEdit.fixture.reopen", app, fixed: true); tap("projectEdit.restore", app)
        saved = try snapshot(app); XCTAssertEqual(try pendingCount(saved), 0)
        XCTAssertEqual(try blocks(saved)[2]["id"] as? String, blockID); XCTAssertEqual(saved["storyAudioUploadCount"] as? Int, 1)
    }
}
