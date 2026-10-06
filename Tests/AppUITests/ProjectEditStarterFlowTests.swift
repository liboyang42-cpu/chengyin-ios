import XCTest

/// Authored complete synthetic methods. No Apple execution or live publication claim.
@MainActor final class ProjectEditStarterFlowTests: XCTestCase {
    private var app: XCUIApplication?
    private struct Snapshot: Decodable {
        struct Draft: Decodable {
            struct Chapter: Decodable {
                struct Node: Decodable { let name: String; let longitude: String; let latitude: String }
                let name: String; let nodes: [Node]
            }
            let product: Int; let chapters: [Chapter]
        }
        let savedDraft: Draft?
        let submissionCount: Int
        let inspectionSequence: Int
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String]) -> XCUIApplication {
        app?.terminate()
        let value = XCUIApplication(); app = value
        value.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-edit-free-explore", "--project-edit-starter-probe"] + flags
        value.launch(); XCTAssertTrue(value.textFields["projectEdit.name"].waitForExistence(timeout: 5)); return value
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        XCTAssertTrue(revealFixtureElement(element, in: app, towardTop: towardTop, maximumSwipes: 40), app.debugDescription)
    }
    private func fixedTap(_ id: String, in app: XCUIApplication) {
        let button = app.buttons[id]; XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertTrue(button.isHittable, app.debugDescription); XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame), app.debugDescription); button.tap()
    }
    private func enter(_ id: String, text: String, in app: XCUIApplication) {
        let field = app.textFields[id]; reveal(field, in: app); field.tap(); field.typeText(text)
        let accepted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [accepted], timeout: 5), .completed, app.debugDescription)
    }
    private func inspect(_ app: XCUIApplication) throws -> Snapshot {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (app.buttons["projectStarter.fixtureSnapshot"].value as? String) ?? ""
        fixedTap("projectStarter.fixtureSnapshot", in: app)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(try XCTUnwrap(probe.value as? String).utf8))
        XCTAssertEqual(snapshot.submissionCount, 0); XCTAssertGreaterThan(snapshot.inspectionSequence, 0)
        XCTAssertFalse(app.alerts.firstMatch.exists); XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        return snapshot
    }
    // UNMEASURED full new-method estimate: 480s (two launches, cancel/restore and explicit add/save).
    func testFreeStarterCancelsWithoutGhostNodeThenExplicitlyAddsAndSavesFirstNode() throws {
        var app = launch(["--project-edit-blank"])
        var create = app.buttons["projectEdit.addChapter"]; reveal(create, in: app); XCTAssertEqual(create.label, "Create chapter"); create.tap()
        XCTAssertTrue(app.textFields["projectEdit.nodeName"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["projectStarter.addText"].exists)
        XCTAssertFalse(app.buttons["projectStarter.finishNode"].isEnabled)
        enter("projectEdit.nodeName", text: "Discarded candidate", in: app)
        fixedTap("projectStarter.close", in: app); fixedTap("projectEdit.saveLocal", in: app)
        var draft = try XCTUnwrap(try inspect(app).savedDraft)
        XCTAssertEqual(draft.product, 2); XCTAssertEqual(draft.chapters.count, 1); XCTAssertEqual(draft.chapters[0].name, "Chapter 1"); XCTAssertTrue(draft.chapters[0].nodes.isEmpty)
        fixedTap("projectEdit.fixture.reopen", in: app)
        let restore = app.buttons["projectEdit.restore"]; XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.tap()
        fixedTap("projectEdit.saveLocal", in: app)
        draft = try XCTUnwrap(try inspect(app).savedDraft); XCTAssertEqual(draft.chapters.count, 1); XCTAssertTrue(draft.chapters[0].nodes.isEmpty)

        app = launch(["--project-edit-blank"])
        create = app.buttons["projectEdit.addChapter"]; reveal(create, in: app); create.tap()
        enter("projectEdit.nodeName", text: "Exploration node", in: app)
        enter("projectEdit.longitude", text: "121.5", in: app); enter("projectEdit.latitude", text: "31.2", in: app)
        fixedTap("projectStarter.finishNode", in: app); fixedTap("projectEdit.saveLocal", in: app)
        draft = try XCTUnwrap(try inspect(app).savedDraft)
        XCTAssertEqual(draft.product, 2); XCTAssertEqual(draft.chapters.count, 1); XCTAssertEqual(draft.chapters[0].nodes.count, 1)
        XCTAssertEqual(draft.chapters[0].nodes[0].name, "Exploration node")
        XCTAssertEqual(draft.chapters[0].nodes[0].longitude, "121.5"); XCTAssertEqual(draft.chapters[0].nodes[0].latitude, "31.2")
    }
    // UNMEASURED full new-method estimate: 240s (one launch, existing explicit opening and back).
    func testFreeExplicitOpeningKeepsSharedStoryEditorWithoutFormalNodeAction() throws {
        let app = launch(["--project-edit-opening"])
        let chapter = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectEdit.chapter.")).firstMatch
        reveal(chapter, in: app); chapter.tap()
        let story = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectEdit.block.")).firstMatch
        reveal(story, in: app); XCTAssertEqual(story.value as? String, "Shared opening story")
        let addNode = app.buttons["projectEdit.addNode"]; reveal(addNode, in: app); XCTAssertFalse(addNode.isEnabled)
        XCTAssertFalse(app.buttons["projectStarter.finishNode"].exists)
        let back = app.navigationBars.buttons.firstMatch; XCTAssertTrue(back.isHittable); back.tap()
        fixedTap("projectEdit.saveLocal", in: app)
        let draft = try XCTUnwrap(try inspect(app).savedDraft)
        XCTAssertEqual(draft.product, 2); XCTAssertEqual(draft.chapters.count, 1); XCTAssertTrue(draft.chapters[0].nodes.isEmpty)
    }
}
