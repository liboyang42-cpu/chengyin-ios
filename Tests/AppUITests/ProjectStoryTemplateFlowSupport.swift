import XCTest

/// Real story controls and persisted local envelopes, with an in-memory personal draft reader.
/// These journeys never call a live API, open a picker, load remote images, or submit a project.
@MainActor final class ProjectStoryTemplateFlowSupport {
    private var app: XCUIApplication?
    enum Gap: Equatable { case first, middle, end }
    enum Kind: Equatable {
        case game, album
        var id: String { self == .game ? "811" : "812" }
        var title: String { self == .game ? "Synthetic story game" : "Synthetic album" }
    }

    /// Decode all persisted fields, including unknown local metadata, with byte-exact strings.
    private enum Value: Decodable, Equatable {
        case null, bool(Bool), number(Decimal), string(String), array([Value]), object([String: Value])
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Decimal.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([Value].self) { self = .array(value) }
            else { self = .object(try container.decode([String: Value].self)) }
        }
        var object: [String: Value]? { if case .object(let value) = self { return value }; return nil }
        var array: [Value]? { if case .array(let value) = self { return value }; return nil }
        var text: String? { if case .string(let value) = self { return value }; return nil }
        static func == (left: Value, right: Value) -> Bool {
            switch (left, right) {
            case (.null, .null): return true
            case (.bool(let lhs), .bool(let rhs)): return lhs == rhs
            case (.number(let lhs), .number(let rhs)): return lhs == rhs
            case (.string(let lhs), .string(let rhs)): return lhs.utf8.elementsEqual(rhs.utf8)
            case (.array(let lhs), .array(let rhs)): return lhs == rhs
            case (.object(let lhs), .object(let rhs)): return lhs == rhs
            default: return false
            }
        }
    }
    private struct Snapshot: Decodable {
        let inspectionSequence: Int, submissionCount: Int
        let storyTemplateListCount: Int, storyTemplateDetailCount: Int
        let savedDraft: Value
    }
    private static let imageURLs = [
        "https://example.com/synthetic/story/e%CC%81.jpg?version=1",
        "https://example.com/synthetic/story/second.jpg?version=2"
    ]
    private static let captions = ["Synthetic e\u{301} caption", "Second synthetic caption"]

    func finish(_ test: XCTestCase) { attachFailureScreenshot(test, app: app); app?.terminate(); app = nil }
    private func tap(_ id: String, _ app: XCUIApplication, fixed: Bool = false, top: Bool = false) {
        let button = app.buttons[id]
        if !fixed { XCTAssertTrue(revealFixtureElement(button, in: app, towardTop: top, maximumSwipes: 10), app.debugDescription) }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: button)], timeout: 5), .completed)
        XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame)); button.tap()
    }
    private func snapshot(_ app: XCUIApplication) throws -> Snapshot {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (probe.value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", app, fixed: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)], timeout: 5), .completed)
        let value = try JSONDecoder().decode(Snapshot.self, from: Data(try XCTUnwrap(probe.value as? String).utf8))
        XCTAssertGreaterThan(value.inspectionSequence, 0); XCTAssertEqual(value.submissionCount, 0)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        return value
    }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "--uitesting-module", "projectEdit", "--project-edit-starter-probe", "--project-edit-pending", "--project-story-template"]
        app.launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5))
        assertFixtureEnvironment(in: app, dynamicTypeSize: "large")
        tap("projectEdit.saveLocal", app, fixed: true); return app
    }
    private func backToEditor(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); button.tap()
        let editorAction = app.navigationBars["Route editor"].buttons["Edit"]
        let arrived = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: editorAction)], timeout: 5) == .completed
        var diagnostic = ""
        if !arrived {
            let lateNameExists = app.textFields["projectEdit.name"].exists
            let lateChapterVisible = app.navigationBars["Chapter"].exists
            let lateCloseVisible = app.buttons["projectStoryTemplate.close"].exists
            diagnostic = "STORY_TEMPLATE_BACK AFTER_TIMEOUT_ONLY nameExists=\(lateNameExists) chapterVisible=\(lateChapterVisible) closeVisible=\(lateCloseVisible)"
        }
        XCTAssertTrue(arrived, diagnostic)
    }
    private func open(before anchor: String?, chapterID: String, _ app: XCUIApplication) {
        tap("projectEdit.chapter." + chapterID, app)
        if let anchor {
            tap("projectStoryMedia.gap." + anchor, app)
            tap("projectStoryTemplate.insertBefore." + anchor, app, fixed: true)
        } else { tap("projectStoryTemplate.add", app) }
        XCTAssertTrue(app.buttons["projectStoryTemplate.refresh"].waitForExistence(timeout: 5))
    }
    private func preview(_ kind: Kind, _ app: XCUIApplication) {
        tap("projectStoryTemplate.row." + kind.id, app)
        let title = app.staticTexts["projectStoryTemplate.preview.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(Array(title.label.utf8), Array(kind.title.utf8))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "projectStoryTemplate.preview").firstMatch.exists)
        XCTAssertFalse(app.textFields["projectStoryTemplate.preview.title"].exists)
        if kind == .game {
            let reference = app.descendants(matching: .any).matching(identifier: "projectStoryTemplate.preview.templateID").firstMatch
            XCTAssertTrue(reference.exists)
            XCTAssertTrue(reference.label.contains(kind.id) || (reference.value as? String)?.contains(kind.id) == true || reference.staticTexts[kind.id].exists)
            XCTAssertFalse(app.staticTexts["projectStoryTemplate.preview.image.0"].exists)
        } else {
            for index in Self.imageURLs.indices {
                let image = app.staticTexts["projectStoryTemplate.preview.image.\(index)"]
                let caption = app.staticTexts["projectStoryTemplate.preview.caption.\(index)"]
                XCTAssertTrue(image.exists); XCTAssertTrue(caption.exists)
                XCTAssertEqual(Array(image.label.utf8), Array(Self.imageURLs[index].utf8))
                XCTAssertEqual(Array(caption.label.utf8), Array(Self.captions[index].utf8))
            }
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "projectStoryTemplate.preview.templateID").firstMatch.exists)
        }
    }
    private func waitForDismissal(_ app: XCUIApplication) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["projectStoryTemplate.close"])], timeout: 5), .completed)
    }

    func journey(_ kind: Kind, gap: Gap) throws {
        let app = launch(), initial = try snapshot(app)
        var originalDraft = try XCTUnwrap(initial.savedDraft.object)
        var chapters = try XCTUnwrap(originalDraft["chapters"]?.array)
        var chapter = try XCTUnwrap(chapters.first?.object)
        let chapterID = try XCTUnwrap(chapter["id"]?.text)
        let originalBlocks = try XCTUnwrap(chapter["blocks"]?.array)
        let originalNodes = try XCTUnwrap(chapter["nodes"]?.array)
        let pending = try XCTUnwrap(originalDraft["pendingMaterials"]?.array)
        XCTAssertEqual(originalBlocks.count, 2); XCTAssertEqual(originalNodes.count, 1); XCTAssertEqual(pending.count, 1)
        let position = gap == .first ? 0 : gap == .middle ? 1 : originalBlocks.count
        let anchor: String? = position < originalBlocks.count ? try XCTUnwrap(originalBlocks[position].object?["id"]?.text) : nil
        XCTAssertEqual(initial.storyTemplateListCount, 0); XCTAssertEqual(initial.storyTemplateDetailCount, 0)

        // Both preview navigation paths are read-only; Refresh is an explicit fresh list read.
        open(before: anchor, chapterID: chapterID, app); preview(kind, app)
        tap("projectStoryTemplate.back", app); tap("projectStoryTemplate.refresh", app)
        preview(kind, app); tap("projectStoryTemplate.close", app, fixed: true)
        waitForDismissal(app); backToEditor(app)
        let cancelled = try snapshot(app)
        XCTAssertEqual(cancelled.savedDraft, initial.savedDraft)
        XCTAssertEqual(cancelled.storyTemplateListCount, 2); XCTAssertEqual(cancelled.storyTemplateDetailCount, 2)

        // A new opening rereads the shelf; Apply rereads the selected source before saving.
        open(before: anchor, chapterID: chapterID, app); preview(kind, app)
        tap("projectStoryTemplate.apply", app); waitForDismissal(app); backToEditor(app)
        let applied = try snapshot(app)
        XCTAssertEqual(applied.storyTemplateListCount, 3); XCTAssertEqual(applied.storyTemplateDetailCount, 4)
        let appliedChapter = try XCTUnwrap(applied.savedDraft.object?["chapters"]?.array?.first?.object)
        let blocks = try XCTUnwrap(appliedChapter["blocks"]?.array)
        let nodes = try XCTUnwrap(appliedChapter["nodes"]?.array)
        XCTAssertEqual(blocks.count, originalBlocks.count + 1)
        let inserted = try XCTUnwrap(blocks[position].object), insertedID = try XCTUnwrap(inserted["id"]?.text)
        XCTAssertFalse(originalBlocks.contains { $0.object?["id"]?.text == insertedID })
        XCTAssertEqual(blocks.enumerated().filter { $0.offset != position }.map(\.element), originalBlocks)
        XCTAssertEqual(inserted["content"], .string("")); XCTAssertEqual(inserted["url"], .string(""))
        if kind == .game {
            XCTAssertEqual(inserted["kind"], .string("node"))
            XCTAssertEqual(inserted["sourceFields"], .object(["locationRequired": .bool(false)]))
            let nodeID = try XCTUnwrap(inserted["nodeID"]?.text)
            XCTAssertEqual(nodes.count, originalNodes.count + 1); XCTAssertEqual(Array(nodes.dropLast()), originalNodes)
            let node = try XCTUnwrap(nodes.last?.object)
            XCTAssertEqual(node["id"], .string(nodeID)); XCTAssertEqual(node["name"], .string(kind.title))
            XCTAssertEqual(node["templateID"], .number(811))
            XCTAssertEqual(node["longitude"], .string("")); XCTAssertEqual(node["latitude"], .string(""))
            XCTAssertEqual(node["localMetadata"], .object([:]))
            XCTAssertFalse(originalNodes.contains { $0.object?["id"]?.text == nodeID })
        } else {
            XCTAssertEqual(inserted["kind"], .string("dream")); XCTAssertEqual(inserted["nodeID"], .string(""))
            XCTAssertEqual(nodes, originalNodes)
            let images = Self.imageURLs.indices.map { index in
                Value.object(["url": .string(Self.imageURLs[index]), "line": .string(Self.captions[index])])
            }
            XCTAssertEqual(inserted["sourceFields"], .object(["title": .string(kind.title), "images": .array(images)]))
        }
        chapter["blocks"] = .array(blocks); chapter["nodes"] = .array(nodes)
        chapters[0] = .object(chapter); originalDraft["chapters"] = .array(chapters)
        // Everything outside the exact insertion remains unchanged, including pending materials.
        XCTAssertEqual(applied.savedDraft, .object(originalDraft))
        XCTAssertEqual(applied.savedDraft.object?["pendingMaterials"], .array(pending))

        // Rebuild the real coordinator, then restore the stored envelope rather than reusing it.
        tap("projectEdit.fixture.reopen", app, fixed: true); tap("projectEdit.restore", app)
        // Resave the restored editor state so the probe cannot pass by merely rereading
        // an untouched old envelope while the visible coordinator failed to restore it.
        tap("projectEdit.saveLocal", app, fixed: true)
        let restored = try snapshot(app)
        XCTAssertEqual(restored.savedDraft, applied.savedDraft)
        XCTAssertEqual(restored.storyTemplateListCount, 3); XCTAssertEqual(restored.storyTemplateDetailCount, 4)
        open(before: anchor, chapterID: chapterID, app); preview(kind, app)
        tap("projectStoryTemplate.close", app, fixed: true); waitForDismissal(app); backToEditor(app)
        let reopened = try snapshot(app)
        XCTAssertEqual(reopened.savedDraft, applied.savedDraft)
        XCTAssertEqual(reopened.storyTemplateListCount, 4); XCTAssertEqual(reopened.storyTemplateDetailCount, 5)
        // First-position gameplay can be invalid for publication under existing story rules.
        // Local adoption and persistence never imply that publication is available.
    }
}
