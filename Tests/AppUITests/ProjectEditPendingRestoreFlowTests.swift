import XCTest

/// Complete synthetic local flows. No live publication, picker, location or network request.
@MainActor final class ProjectEditPendingRestoreFlowTests: XCTestCase {
    private var app: XCUIApplication?
    private struct Snapshot: Decodable {
        struct Node: Decodable { let id: String; let name: String; let longitude: String; let latitude: String }
        struct Material: Decodable { let kind: String; let node: Node }
        struct Chapter: Decodable {
            struct Block: Decodable { let kind: String; let content: String; let nodeID: String }
            let id: String; let name: String; let nodes: [Node]; let blocks: [Block]?
        }
        struct Draft: Decodable { let product: Int; let chapters: [Chapter]; let pendingMaterials: [Material]? }
        let savedDraft: Draft?; let submissionCount: Int; let inspectionSequence: Int
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String], city: Bool = false) -> XCUIApplication {
        let value = XCUIApplication(); app = value
        value.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-edit-starter-probe"] + (city ? [] : ["--project-edit-free-explore"]) + flags
        value.launch(); XCTAssertTrue(value.textFields["projectEdit.name"].waitForExistence(timeout: 5)); return value
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        XCTAssertTrue(revealFixtureElement(element, in: app, towardTop: towardTop, maximumSwipes: 48), app.debugDescription)
    }
    private func tap(_ id: String, in app: XCUIApplication, fixed: Bool = false) {
        let button = app.buttons[id]
        if !fixed { reveal(button, in: app) }
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable, app.debugDescription); XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame), app.debugDescription); button.tap()
    }
    private func enter(_ id: String, value: String, in app: XCUIApplication) {
        let field = app.textFields[id]; reveal(field, in: app); field.tap(); field.typeText(value)
        let accepted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [accepted], timeout: 5), .completed, app.debugDescription)
    }
    private func inspect(_ app: XCUIApplication) throws -> Snapshot {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (app.buttons["projectStarter.fixtureSnapshot"].value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", in: app, fixed: true)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(try XCTUnwrap(probe.value as? String).utf8))
        XCTAssertEqual(snapshot.submissionCount, 0); XCTAssertGreaterThan(snapshot.inspectionSequence, 0)
        XCTAssertFalse(app.alerts.firstMatch.exists); XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        return snapshot
    }
    private func choose(_ chapter: Snapshot.Chapter, in app: XCUIApplication) {
        let direct = app.buttons["projectPending.chapter." + chapter.id]
        if direct.exists && direct.isHittable {
            XCTAssertEqual(app.buttons.matching(identifier: "projectPending.chapter." + chapter.id).count, 1)
            XCTAssertTrue(direct.isEnabled); XCTAssertTrue(app.windows.firstMatch.frame.contains(direct.frame)); direct.tap(); return
        }
        // Native Menu may expose its exact rendered title instead of the SwiftUI identifier.
        let choices = app.buttons.matching(NSPredicate(format: "label == %@", chapter.name)).allElementsBoundByIndex.filter {
            $0.isHittable && $0.isEnabled && app.windows.firstMatch.frame.contains($0.frame)
        }
        XCTAssertEqual(choices.count, 1, app.debugDescription); guard choices.count == 1 else { return }; choices[0].tap()
    }
    // UNMEASURED full new-method estimate:660s, including two actual restore cycles.
    func testFreeIncompleteMaterialSurvivesRestoreCancelEditAndExplicitChapterPlacement() throws {
        let app = launch(["--project-edit-blank"])
        tap("projectEdit.addChapter", in: app); enter("projectEdit.nodeName", value: "Pending exploration", in: app)
        XCTAssertEqual(app.buttons["projectStarter.finishNode"].label, "Save to pending materials")
        tap("projectStarter.finishNode", in: app, fixed: true)
        var saved = try XCTUnwrap(try inspect(app).savedDraft), material = try XCTUnwrap(saved.pendingMaterials?.first)
        XCTAssertEqual(saved.product, 2); XCTAssertTrue(saved.chapters[0].nodes.isEmpty); XCTAssertEqual(material.node.name, "Pending exploration")
        tap("projectEdit.fixture.reopen", in: app, fixed: true); tap("projectEdit.restore", in: app)
        tap("projectPending.edit." + material.node.id, in: app)
        enter("projectEdit.longitude", value: "121.5", in: app); enter("projectEdit.latitude", value: "31.2", in: app)
        tap("projectPending.close", in: app, fixed: true)
        saved = try XCTUnwrap(try inspect(app).savedDraft); material = try XCTUnwrap(saved.pendingMaterials?.first)
        XCTAssertEqual(material.node.longitude, ""); XCTAssertEqual(material.node.latitude, ""); XCTAssertTrue(saved.chapters[0].nodes.isEmpty)
        tap("projectPending.edit." + material.node.id, in: app)
        enter("projectEdit.longitude", value: "121.5", in: app); enter("projectEdit.latitude", value: "31.2", in: app)
        tap("projectPending.save", in: app, fixed: true)
        saved = try XCTUnwrap(try inspect(app).savedDraft); material = try XCTUnwrap(saved.pendingMaterials?.first)
        XCTAssertEqual(material.node.longitude, "121.5"); XCTAssertEqual(material.node.latitude, "31.2")
        tap("projectPending.arrange." + material.node.id, in: app); choose(saved.chapters[0], in: app)
        saved = try XCTUnwrap(try inspect(app).savedDraft)
        XCTAssertEqual(saved.pendingMaterials?.count, 0); XCTAssertEqual(saved.chapters[0].nodes.map(\.id), [material.node.id])
        tap("projectEdit.fixture.reopen", in: app, fixed: true); tap("projectEdit.restore", in: app)
        saved = try XCTUnwrap(try inspect(app).savedDraft)
        XCTAssertEqual(saved.pendingMaterials?.count, 0); XCTAssertEqual(saved.chapters[0].nodes[0].name, "Pending exploration")
    }
    // UNMEASURED full new-method estimate:420s, actual city story edit/back/explicit insertion.

    // UNMEASURED full new-method estimate:240s, failed actual store write retains the form/candidate.

}
