import XCTest

/// Complete generated-image journey. No Photos permission, real files, network, or live upload.
@MainActor final class ProjectStoryImageFlowTests: XCTestCase {
    private var app: XCUIApplication?
    private struct Snapshot: Decodable {
        struct Draft: Decodable {
            struct Chapter: Decodable {
                struct Block: Decodable { let id: String, kind: String, url: String }
                let id: String, blocks: [Block]?
            }
            let chapters: [Chapter]
        }
        let inspectionSequence: Int, submissionCount: Int, storyImageUploadCount: Int
        let storyImageReference: String, savedDraft: Draft
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, top: Bool = false, tap: Bool = true) {
        XCTAssertTrue(revealFixtureElement(element, in: app, towardTop: top, maximumSwipes: 45, requiresHittable: tap), app.debugDescription)
    }
    private func tap(_ id: String, _ app: XCUIApplication, fixed: Bool = false) {
        let button = app.buttons[id]; if !fixed { reveal(button, app) }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame)); button.tap()
    }
    private func inspect(_ app: XCUIApplication) throws -> Snapshot {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (probe.value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", app, fixed: true)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let value = try JSONDecoder().decode(Snapshot.self, from: Data(try XCTUnwrap(probe.value as? String).utf8))
        XCTAssertEqual(value.submissionCount, 0); XCTAssertGreaterThan(value.inspectionSequence, 0)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        return value
    }
    private func choose(_ app: XCUIApplication) {
        tap("projectStoryImage.choose", app); tap("template.imageCrop.confirm", app)
        XCTAssertTrue(app.images["projectStoryImage.localPreview"].exists)
        XCTAssertTrue(app.staticTexts["projectStoryImage.notUploaded"].exists)
    }
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); button.tap()
    }
    // UNMEASURED complete-method estimate: 900 seconds. Add/cancel/upload/apply, restore, replace, exact prepared readback.
    func testChosenStoryImageAppliesOnlyAfterUploadAndRestoresIntoExactPreparedOrder() throws {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-edit-starter-probe", "--project-story-image"]
        app.launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5)); assertFixtureEnvironment(in: app, dynamicTypeSize: "large")
        tap("projectEdit.saveLocal", app, fixed: true); var saved = try inspect(app)
        let chapter = saved.savedDraft.chapters[0]; XCTAssertEqual(chapter.blocks?.count, 2); XCTAssertEqual(saved.storyImageUploadCount, 0)
        tap("projectEdit.chapter." + chapter.id, app); tap("projectStoryImage.add", app)
        choose(app); tap("projectStoryImage.cancelLocal", app); XCTAssertFalse(app.buttons["projectStoryImage.upload"].exists)
        choose(app); tap("projectStoryImage.upload", app)
        let reference = app.staticTexts["projectStoryImage.reference"]; XCTAssertTrue(reference.waitForExistence(timeout: 5))
        XCTAssertEqual(Array(reference.label.utf8), Array("https://example.com/synthetic/story/e%CC%81.jpg?version=1".utf8))
        tap("projectStoryImage.apply", app); XCTAssertFalse(app.buttons["projectStoryImage.close"].exists); back(app)
        saved = try inspect(app); XCTAssertEqual(saved.storyImageUploadCount, 1)
        let image = try XCTUnwrap(saved.savedDraft.chapters[0].blocks?.last)
        XCTAssertEqual(image.kind, "image"); XCTAssertEqual(saved.savedDraft.chapters[0].blocks?.count, 3)
        XCTAssertEqual(Array(image.url.utf8), Array(saved.storyImageReference.utf8))
        tap("projectEdit.fixture.reopen", app, fixed: true)
        let restore = app.buttons["projectEdit.restore"]; XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.tap()
        tap("projectEdit.saveLocal", app, fixed: true); saved = try inspect(app)
        XCTAssertEqual(saved.savedDraft.chapters[0].blocks?.last?.id, image.id); XCTAssertEqual(saved.storyImageUploadCount, 1)
        tap("projectEdit.chapter." + chapter.id, app); tap("projectStoryImage.replace." + image.id, app)
        choose(app); tap("projectStoryImage.upload", app); XCTAssertTrue(reference.waitForExistence(timeout: 5))
        XCTAssertEqual(Array(reference.label.utf8), Array("https://example.com/synthetic/story/e%CC%81.jpg?version=2".utf8))
        tap("projectStoryImage.apply", app); back(app); saved = try inspect(app)
        XCTAssertEqual(saved.storyImageUploadCount, 2); XCTAssertEqual(saved.savedDraft.chapters[0].blocks?.count, 3)
        XCTAssertEqual(saved.savedDraft.chapters[0].blocks?.last?.id, image.id)
        XCTAssertEqual(Array(try XCTUnwrap(saved.savedDraft.chapters[0].blocks?.last?.url).utf8), Array(saved.storyImageReference.utf8))
        tap("projectEdit.review", app, fixed: true)
        let prepared = app.staticTexts["projectStoryImage.prepared.0.2"]; reveal(prepared, app, tap: false)
        XCTAssertEqual(Array(prepared.label.utf8), Array(saved.storyImageReference.utf8))
        XCTAssertFalse(app.images["projectStoryImage.localPreview"].exists)
        tap("projectEdit.cancelReview", app)
        XCTAssertEqual(try inspect(app).storyImageUploadCount, 2)
    }
}
