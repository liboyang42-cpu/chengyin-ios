import XCTest

/// Synthetic actual pending-host actions; no provider, user file or live network.
@MainActor final class ProjectPendingStoryImageFlowTests: XCTestCase {
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
    // UNMEASURED complete-method estimate: 900 seconds. New pending chapter, crop cancel/apply, Back, restore and exact local reference.
    func testPendingNewStoryChapterCanChooseCancelAndApplyImageWithoutPlacingMaterial() throws {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-edit-starter-probe", "--project-edit-pending", "--project-pending-no-chapters", "--project-story-image", "--project-story-audio"]
        app.launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5)); assertFixtureEnvironment(in: app, dynamicTypeSize: "large")
        tap("projectEdit.saveLocal", app, fixed: true); let before = try snapshot(app), materialID = try material(before)
        tap("projectPending.newChapter." + materialID, app)
        XCTAssertTrue(app.buttons["projectPending.close"].waitForExistence(timeout: 5))
        tap("projectStoryImage.add", app); tap("projectStoryImage.choose", app); tap("template.imageCrop.cancel", app)
        XCTAssertFalse(app.buttons["projectStoryImage.upload"].exists)
        tap("projectStoryImage.choose", app); tap("template.imageCrop.confirm", app)
        XCTAssertTrue(app.images["projectStoryImage.localPreview"].exists); XCTAssertTrue(app.staticTexts["projectStoryImage.notUploaded"].exists)
        tap("projectStoryImage.upload", app)
        let exact = "https://example.com/synthetic/story/e%CC%81.jpg?version=1", uploaded = app.staticTexts["projectStoryImage.reference"]
        XCTAssertTrue(uploaded.waitForExistence(timeout: 5)); XCTAssertEqual(Array(uploaded.label.utf8), Array(exact.utf8))
        tap("projectStoryImage.apply", app); XCTAssertFalse(app.buttons["projectStoryImage.close"].exists)
        XCTAssertTrue(app.buttons["projectPending.close"].exists)
        let insert = app.buttons["projectPending.insert.end"]
        XCTAssertTrue(revealFixtureElement(insert, in: app, maximumSwipes: 45, requiresHittable: false)); XCTAssertFalse(insert.isEnabled)
        tap("projectPending.close", app, fixed: true); var saved = try snapshot(app)
        XCTAssertEqual(try pendingCount(saved), 1); XCTAssertEqual(try material(saved), materialID)
        XCTAssertEqual(saved["storyImageUploadCount"] as? Int, 1); XCTAssertEqual(saved["storyAudioUploadCount"] as? Int, 0)
        let currentChapter = try chapter(saved), block = try XCTUnwrap(blocks(saved).first), blockID = try XCTUnwrap(block["id"] as? String)
        XCTAssertEqual(try blocks(saved).count, 1); XCTAssertEqual(block["kind"] as? String, "image")
        XCTAssertEqual(Array(try XCTUnwrap(block["url"] as? String).utf8), Array(exact.utf8))
        tap("projectEdit.fixture.reopen", app, fixed: true); tap("projectEdit.restore", app)
        saved = try snapshot(app); XCTAssertEqual(try material(saved), materialID); XCTAssertEqual(try blocks(saved).first?["id"] as? String, blockID)
        chooseChapter(app, materialID: materialID, name: try XCTUnwrap(currentChapter["name"] as? String))
        tap("projectStoryImage.replace." + blockID, app)
        let original = app.staticTexts["projectStoryImage.savedReference"]
        XCTAssertTrue(original.waitForExistence(timeout: 5)); XCTAssertEqual(Array(original.label.utf8), Array(exact.utf8))
        tap("projectStoryImage.close", app, fixed: true); tap("projectPending.close", app, fixed: true)
        saved = try snapshot(app); XCTAssertEqual(saved["storyImageUploadCount"] as? Int, 1); XCTAssertEqual(try pendingCount(saved), 1)
    }
}
