import XCTest

/// Real synthetic edit/save/restore/review controls. No backend publication or arbitrary media fetch.
@MainActor final class ProjectEditPreparedStoryOrderFlowTests: XCTestCase {
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
        value.launch(); XCTAssertTrue(revealFixtureElement(value.textFields["projectEdit.name"], in: value, maximumSwipes: 10, requiresHittable: false)); XCTAssertTrue(value.textFields["projectEdit.name"].waitForExistence(timeout: 5)); return value
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
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let current = field.value as? String, let inserted = current.range(of: text) else { return false }
            var remaining = current; remaining.removeSubrange(inserted)
            return Array(remaining.utf8) == Array(original.utf8)
        }, object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        let current = try XCTUnwrap(field.value as? String)
        XCTAssertEqual(Array(current.replacingOccurrences(of: text, with: "").utf8), Array(original.utf8))
        return current
    }
    private func read(_ field: String, node: Int, expected: String, in app: XCUIApplication) {
        let value = app.descendants(matching: .any)["projectPrepared.chapter.0.node.\(node)." + field].firstMatch
        reveal(value, in: app, hittable: false); XCTAssertEqual(Array(value.label.utf8), Array(expected.utf8), app.debugDescription)
    }
    // UNMEASURED full-method allowance:680s. Retained630s floor plus two22s read-only launch reveals, rounded up; both original journeys remain complete.
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
