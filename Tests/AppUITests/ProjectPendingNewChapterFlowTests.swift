import XCTest

/// Full synthetic button flows, unexecuted on Apple tooling for this source packet.
@MainActor final class ProjectPendingNewChapterFlowTests: XCTestCase {
    private var app: XCUIApplication?
    private struct Snapshot: Decodable {
        struct Node: Decodable { let id: String; let name: String; let description: String; let longitude: String; let latitude: String }
        struct Material: Decodable { let node: Node }
        struct Chapter: Decodable {
            struct Block: Decodable { let kind: String; let content: String; let nodeID: String }
            let id: String; let name: String; let nodes: [Node]; let blocks: [Block]?
        }
        struct Draft: Decodable { let product: Int; let chapters: [Chapter]; let pendingMaterials: [Material]? }
        let savedDraft: Draft?; let submissionCount: Int; let inspectionSequence: Int
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String] = [], city: Bool = false) -> XCUIApplication {
        app?.terminate(); let value = XCUIApplication(); app = value
        value.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-edit-starter-probe", "--project-edit-pending", "--project-pending-no-chapters"] + (city ? [] : ["--project-edit-free-explore"]) + flags
        value.launch(); XCTAssertTrue(value.textFields["projectEdit.name"].waitForExistence(timeout: 5)); return value
    }
    private func reveal(_ value: XCUIElement, in app: XCUIApplication, top: Bool = false, hittable: Bool = true) {
        XCTAssertTrue(revealFixtureElement(value, in: app, towardTop: top, maximumSwipes: 60, requiresHittable: hittable), app.debugDescription)
    }
    private func tap(_ id: String, in app: XCUIApplication, fixed: Bool = false) {
        let button = app.buttons[id]
        if !fixed { reveal(button, in: app) }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(button.isHittable && button.isEnabled)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame)); button.tap()
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
    private func enter(_ id: String, value: String, in app: XCUIApplication) {
        let field = app.textFields[id]; reveal(field, in: app); field.tap(); field.typeText(value)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: field)], timeout: 5), .completed)
    }
    // UNMEASURED complete new-method estimate: 720 seconds, including both launches and restore.
    func testFreeNewChapterRequiresCoordinatesThenSavesTogetherAndFailureKeepsMaterial() throws {
        var app = launch(["--project-pending-missing-coordinates"])
        tap("projectEdit.saveLocal", in: app, fixed: true)
        var saved = try XCTUnwrap(try inspect(app).savedDraft); let row = try XCTUnwrap(saved.pendingMaterials?.first)
        XCTAssertTrue(saved.chapters.isEmpty)
        tap("projectPending.newChapter." + row.node.id, in: app)
        XCTAssertTrue(app.buttons["projectPending.save"].waitForExistence(timeout: 5))
        tap("projectPending.close", in: app, fixed: true)
        XCTAssertTrue(try XCTUnwrap(try inspect(app).savedDraft).chapters.isEmpty)
        tap("projectPending.newChapter." + row.node.id, in: app)
        enter("projectEdit.longitude", value: "121.5", in: app); enter("projectEdit.latitude", value: "31.2", in: app)
        tap("projectPending.save", in: app, fixed: true)
        tap("projectPending.newChapter." + row.node.id, in: app)
        saved = try XCTUnwrap(try inspect(app).savedDraft)
        XCTAssertEqual(saved.chapters.count, 1); XCTAssertEqual(saved.chapters[0].name, "Chapter 1"); XCTAssertNil(saved.chapters[0].blocks)
        XCTAssertEqual(saved.chapters[0].nodes.map(\.id), [row.node.id]); XCTAssertEqual(saved.pendingMaterials?.count, 0)
        XCTAssertEqual(Array(saved.chapters[0].nodes[0].description.utf8), Array(row.node.description.utf8))
        tap("projectEdit.fixture.reopen", in: app, fixed: true); tap("projectEdit.restore", in: app)
        saved = try XCTUnwrap(try inspect(app).savedDraft); XCTAssertEqual(saved.chapters.count, 1); XCTAssertEqual(saved.pendingMaterials?.count, 0)
        app = launch(["--project-edit-pending-failure"])
        let button = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectPending.newChapter.")).firstMatch
        reveal(button, in: app); let id = button.identifier; tap(id, in: app)
        reveal(app.staticTexts["projectPending.saveUnconfirmed"], in: app, hittable: false)
        XCTAssertTrue(app.buttons[id].exists); XCTAssertNil(try inspect(app).savedDraft)
        XCTAssertFalse(app.buttons["projectPending.close"].exists)
    }
    // UNMEASURED complete new-method estimate: 660 seconds, including Back and explicit story insertion.
    func testCityNewChapterKeepsMaterialThroughBackUntilTextAndChosenSlot() throws {
        let app = launch(city: true); tap("projectEdit.saveLocal", in: app, fixed: true)
        var saved = try XCTUnwrap(try inspect(app).savedDraft); let row = try XCTUnwrap(saved.pendingMaterials?.first)
        tap("projectPending.newChapter." + row.node.id, in: app)
        let insert = app.buttons["projectPending.insert.end"]; reveal(insert, in: app); XCTAssertFalse(insert.isEnabled)
        tap("projectPending.close", in: app, fixed: true)
        saved = try XCTUnwrap(try inspect(app).savedDraft)
        XCTAssertEqual(saved.product, 1); XCTAssertEqual(saved.chapters.count, 1); XCTAssertEqual(saved.chapters[0].blocks?.count, 0)
        XCTAssertTrue(saved.chapters[0].nodes.isEmpty); XCTAssertEqual(saved.pendingMaterials?.first?.node.id, row.node.id)
        tap("projectPending.arrange." + row.node.id, in: app)
        let choices = app.buttons.matching(NSPredicate(format: "label == %@", saved.chapters[0].name)).allElementsBoundByIndex.filter { $0.isEnabled && $0.isHittable }
        XCTAssertEqual(choices.count, 1); guard choices.count == 1 else { return }; XCTAssertTrue(app.windows.firstMatch.frame.contains(choices[0].frame)); choices[0].tap()
        tap("projectStarter.addText", in: app)
        let field = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectEdit.block.")).firstMatch
        reveal(field, in: app, top: true); field.tap(); field.typeText("New chapter story")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "New chapter story"), object: field)], timeout: 5), .completed)
        tap("projectPending.insert.end", in: app)
        saved = try XCTUnwrap(try inspect(app).savedDraft)
        XCTAssertEqual(saved.pendingMaterials?.count, 0); XCTAssertEqual(saved.chapters[0].nodes.map(\.id), [row.node.id])
        XCTAssertEqual(saved.chapters[0].blocks?.map(\.kind), ["text", "node"])
        XCTAssertEqual(saved.chapters[0].blocks?.first?.content, "New chapter story")
        tap("projectEdit.fixture.reopen", in: app, fixed: true); tap("projectEdit.restore", in: app)
        XCTAssertEqual(try XCTUnwrap(try inspect(app).savedDraft).chapters[0].nodes[0].id, row.node.id)
    }
}
