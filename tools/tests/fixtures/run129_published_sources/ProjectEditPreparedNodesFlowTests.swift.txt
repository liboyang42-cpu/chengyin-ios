import XCTest

/// Real synthetic edit/save/restore/review controls. No backend publication or arbitrary media fetch.
@MainActor final class ProjectEditPreparedNodesFlowTests: XCTestCase {
    private var app: XCUIApplication?
    private struct Snapshot: Decodable {
        struct Node: Decodable { let id: String; let name: String; let description: String; let imgUrl: String; let nodeTime: Int; let templateID: Int? }
        struct Chapter: Decodable { let id: String; let name: String; let nodes: [Node] }
        struct Material: Decodable { let node: Node }
        struct Draft: Decodable { let chapters: [Chapter]; let pendingMaterials: [Material]? }
        let savedDraft: Draft?; let submissionCount: Int; let inspectionSequence: Int
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ flags: [String], free: Bool = true) -> XCUIApplication {
        app?.terminate(); let value = XCUIApplication(); app = value
        value.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-edit-starter-probe"] + (free ? ["--project-edit-free-explore"] : []) + flags
        value.launch(); XCTAssertTrue(value.textFields["projectEdit.name"].waitForExistence(timeout: 5)); return value
    }
    private func reveal(_ value: XCUIElement, in app: XCUIApplication, top: Bool = false, hittable: Bool = true) {
        XCTAssertTrue(revealFixtureElement(value, in: app, towardTop: top, maximumSwipes: 60, requiresHittable: hittable), app.debugDescription)
    }
    private func tap(_ id: String, in app: XCUIApplication, fixed: Bool = false) {
        let button = app.buttons[id]; if !fixed { reveal(button, in: app) }
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1); XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame)); button.tap()
    }
    private func back(_ app: XCUIApplication) {
        let buttons = app.navigationBars.buttons.matching(identifier: "BackButton").allElementsBoundByIndex.filter { $0.isHittable }
        XCTAssertEqual(buttons.count, 1, app.debugDescription); guard let button = buttons.first, buttons.count == 1 else { return }; button.tap()
    }
    private func inspect(_ app: XCUIApplication) throws -> Snapshot.Draft {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (app.buttons["projectStarter.fixtureSnapshot"].value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", in: app, fixed: true)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(try XCTUnwrap(probe.value as? String).utf8))
        XCTAssertEqual(snapshot.submissionCount, 0); XCTAssertGreaterThan(snapshot.inspectionSequence, 0)
        XCTAssertFalse(app.alerts.firstMatch.exists); XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        return try XCTUnwrap(snapshot.savedDraft)
    }
    private func insert(_ text: String, into id: String, in app: XCUIApplication) throws -> String {
        let field = app.descendants(matching: .any)[id].firstMatch; reveal(field, in: app)
        let original = try XCTUnwrap(field.value as? String); field.tap(); field.typeText(text)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", original), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        let current = try XCTUnwrap(field.value as? String)
        XCTAssertEqual(Array(current.replacingOccurrences(of: text, with: "").utf8), Array(original.utf8))
        return current
    }
    private func read(_ field: String, node: Int, expected: String, in app: XCUIApplication) {
        let value = app.descendants(matching: .any)["projectPrepared.chapter.0.node.\(node)." + field].firstMatch
        reveal(value, in: app, hittable: false); XCTAssertEqual(Array(value.label.utf8), Array(expected.utf8), app.debugDescription)
    }
    // UNMEASURED full new-method estimate:840s. Actual placement, editing, local save/restore and full node readback.
    func testPlacedMaterialReeditSavesRestoresAndReadsExactPreparedNodeFields() throws {
        let app = launch(["--project-edit-pending", "--project-edit-prepared-values"])
        tap("projectEdit.saveLocal", in: app, fixed: true); var saved = try inspect(app)
        let material = try XCTUnwrap(saved.pendingMaterials?.first), chapter = saved.chapters[0]
        tap("projectPending.arrange." + material.node.id, in: app)
        let choices = app.buttons.matching(NSPredicate(format: "label == %@", chapter.name)).allElementsBoundByIndex.filter { $0.isHittable && $0.isEnabled }
        XCTAssertEqual(choices.count, 1); guard choices.count == 1 else { return }; choices[0].tap()
        tap("projectEdit.chapter." + chapter.id, in: app); tap("projectEdit.node." + material.node.id, in: app)
        let description = try insert("Edited ", into: "projectEdit.nodeDescription", in: app)
        let image = try insert("-edited", into: "projectEdit.nodeImages", in: app)
        tap("projectPrepared.saveNodeDraft", in: app, fixed: true)
        let status = app.staticTexts["projectPrepared.nodeSaveStatus"]; reveal(status, in: app, hittable: false)
        XCTAssertEqual(status.label, "Draft saved on this device only.")
        back(app); back(app); saved = try inspect(app)
        XCTAssertEqual(saved.chapters[0].nodes[1].description, description); XCTAssertEqual(saved.chapters[0].nodes[1].imgUrl, image)
        tap("projectEdit.fixture.reopen", in: app, fixed: true); tap("projectEdit.restore", in: app)
        saved = try inspect(app); XCTAssertEqual(saved.chapters[0].nodes[1].id, material.node.id)
        tap("projectEdit.review", in: app, fixed: true)
        read("name", node: 1, expected: material.node.name, in: app)
        read("description", node: 1, expected: description, in: app)
        read("imgUrl", node: 1, expected: image, in: app)
        read("nodeTime", node: 1, expected: "45", in: app); read("templateId", node: 1, expected: "73", in: app)
        read("sortID", node: 1, expected: "2", in: app)
        tap("projectEdit.cancelReview", in: app)
        XCTAssertEqual(try inspect(app).chapters[0].nodes[1].description, description)
    }
    // UNMEASURED full new-method estimate:540s. Two launches: serialized story order/missing fields and whitelist omission.
    func testPreparedStoryOrderAndMissingFieldsStayDistinctFromWhitelistOmission() throws {
        var app = launch(["--project-edit-prepared-order"], free: false)
        tap("projectEdit.saveLocal", in: app, fixed: true); let saved = try inspect(app)
        XCTAssertEqual(saved.chapters[0].nodes.map(\.name), ["Lighthouse", "Second staged node"])
        tap("projectEdit.review", in: app, fixed: true)
        read("name", node: 0, expected: "Second staged node", in: app); read("sortID", node: 0, expected: "1", in: app)
        read("name", node: 1, expected: "Lighthouse", in: app); read("description", node: 1, expected: "Not included", in: app)
        read("imgUrl", node: 1, expected: "Not included", in: app); read("templateId", node: 1, expected: "Not included", in: app)
        tap("projectEdit.cancelReview", in: app)
        app = launch(["--project-edit-whitelist"], free: false); tap("projectEdit.review", in: app, fixed: true)
        let omitted = app.staticTexts["projectPrepared.omittedChapters"]; reveal(omitted, in: app, hittable: false)
        XCTAssertTrue(omitted.exists); XCTAssertFalse(app.staticTexts["projectPrepared.chapter.0.node.0.name"].exists)
        tap("projectEdit.cancelReview", in: app); _ = try inspect(app)
    }
}
