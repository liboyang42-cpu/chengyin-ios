import XCTest

/// Synthetic bytes only. This journey never opens a document provider or performs network I/O.
@MainActor final class ProjectStoryAudioFlowTests: XCTestCase {
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
    // UNMEASURED complete-method estimate: 900 seconds. Insert/cancel/select/upload/apply, reopen, exact prepared readback and removal.
    func testExistingEmptyBlockReceivesExplicitAudioAndRestoresExactFilenameAndPreparedReference() throws {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-edit-starter-probe", "--project-story-audio", "--project-story-audio-cancel-first"]
        app.launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5)); assertFixtureEnvironment(in: app, dynamicTypeSize: "large")
        XCTAssertTrue(app.staticTexts["projectStoryAudio.fixture.scope"].exists)
        tap("projectEdit.saveLocal", app, fixed: true); var saved = try snapshot(app)
        let chapterID = try XCTUnwrap(chapter(saved)["id"] as? String)
        XCTAssertEqual(try blocks(saved).count, 2); XCTAssertEqual(saved["storyAudioUploadCount"] as? Int, 0)
        tap("projectEdit.chapter." + chapterID, app); tap("projectStoryAudio.add", app); back(app)
        saved = try snapshot(app); let inserted = try XCTUnwrap(blocks(saved).last), blockID = try XCTUnwrap(inserted["id"] as? String)
        XCTAssertEqual(inserted["kind"] as? String, "audio"); XCTAssertEqual(inserted["url"] as? String, "")
        XCTAssertEqual(saved["storyAudioUploadCount"] as? Int, 0)
        tap("projectEdit.chapter." + chapterID, app); tap("projectStoryAudio.open." + blockID, app)
        tap("projectStoryAudio.choose", app); XCTAssertFalse(app.buttons["projectStoryAudio.upload"].exists)
        tap("projectStoryAudio.choose", app)
        XCTAssertTrue(app.staticTexts["projectStoryAudio.notUploaded"].exists)
        XCTAssertEqual(Array(app.staticTexts["projectStoryAudio.filename"].label.utf8), Array("Synthetic e\u{301}.m4a".utf8))
        tap("projectStoryAudio.cancelLocal", app); XCTAssertFalse(app.buttons["projectStoryAudio.upload"].exists)
        tap("projectStoryAudio.choose", app); tap("projectStoryAudio.upload", app)
        let exact = "https://example.com/synthetic/story/e%CC%81.m4a?version=1"
        reference(app, exact); tap("projectStoryAudio.apply", app); XCTAssertFalse(app.buttons["projectStoryAudio.close"].exists); back(app)
        saved = try snapshot(app); let filled = try XCTUnwrap(blocks(saved).last)
        XCTAssertEqual(saved["storyAudioUploadCount"] as? Int, 1); XCTAssertEqual(try blocks(saved).count, 3)
        XCTAssertEqual(filled["id"] as? String, blockID); XCTAssertEqual(Array(try XCTUnwrap(filled["url"] as? String).utf8), Array(exact.utf8))
        let metadata = try XCTUnwrap(filled["localAudio"] as? [String: Any])
        XCTAssertEqual(Array(try XCTUnwrap(metadata["filename"] as? String).utf8), Array("Synthetic e\u{301}.m4a".utf8))
        tap("projectEdit.fixture.reopen", app, fixed: true); tap("projectEdit.restore", app)
        saved = try snapshot(app); XCTAssertEqual(try blocks(saved).last?["id"] as? String, blockID); XCTAssertEqual(saved["storyAudioUploadCount"] as? Int, 1)
        tap("projectEdit.review", app, fixed: true)
        let prepared = app.staticTexts["projectStoryAudio.prepared.0.2"]
        XCTAssertTrue(revealFixtureElement(prepared, in: app, maximumSwipes: 45, requiresHittable: false), app.debugDescription)
        XCTAssertEqual(Array(prepared.label.utf8), Array(exact.utf8)); tap("projectEdit.cancelReview", app)
        tap("projectEdit.chapter." + chapterID, app)
        let filename = app.staticTexts["projectStoryAudio.blockName." + blockID]
        XCTAssertTrue(revealFixtureElement(filename, in: app, maximumSwipes: 45, requiresHittable: false)); XCTAssertEqual(Array(filename.label.utf8), Array("Synthetic e\u{301}.m4a".utf8))
        tap("projectStoryAudio.remove." + blockID, app); back(app); saved = try snapshot(app)
        XCTAssertEqual(try blocks(saved).count, 2); XCTAssertEqual(saved["storyAudioUploadCount"] as? Int, 1)
        tap("projectEdit.fixture.reopen", app, fixed: true); tap("projectEdit.restore", app)
        XCTAssertFalse(try blocks(snapshot(app)).contains { $0["id"] as? String == blockID })
    }
}
