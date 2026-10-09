import XCTest

/// Existing generated media fixtures through real chapter controls, local save and reopen.
/// No Photos/document permissions, real user files, network, or publication.
@MainActor final class ProjectStoryMediaGapFlowSupport {
    private var app: XCUIApplication?
    private struct Snapshot: Decodable {
        struct Draft: Decodable {
            struct Chapter: Decodable {
                struct Block: Decodable, Equatable { let id: String, kind: String, url: String }
                let id: String, blocks: [Block]
            }
            let chapters: [Chapter]
        }
        let inspectionSequence: Int, submissionCount: Int, storyImageUploadCount: Int, storyAudioUploadCount: Int
        let savedDraft: Draft
    }
    func finish(_ test: XCTestCase) { attachFailureScreenshot(test, app: app); app?.terminate(); app = nil }
    private func tap(_ id: String, _ app: XCUIApplication, fixed: Bool = false, top: Bool = false) {
        let button = app.buttons[id]
        if !fixed { XCTAssertTrue(revealFixtureElement(button, in: app, towardTop: top, maximumSwipes: 45), app.debugDescription) }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertEqual(app.buttons.matching(identifier: id).count, 1)
        XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); XCTAssertTrue(app.windows.firstMatch.frame.contains(button.frame)); button.tap()
    }
    private func snapshot(_ app: XCUIApplication) throws -> Snapshot {
        let probe = app.buttons["projectStarter.fixtureSnapshot"], old = (probe.value as? String) ?? ""
        tap("projectStarter.fixtureSnapshot", app, fixed: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", old, "{"), object: probe)], timeout: 5), .completed)
        let value = try JSONDecoder().decode(Snapshot.self, from: Data(try XCTUnwrap(probe.value as? String).utf8))
        XCTAssertGreaterThan(value.inspectionSequence, 0); XCTAssertEqual(value.submissionCount, 0)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists); return value
    }
    private func launch(_ media: String) -> XCUIApplication {
        let app = XCUIApplication(); self.app = app
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-edit-starter-probe", "--project-story-" + media]
        app.launch(); XCTAssertTrue(app.textFields["projectEdit.name"].waitForExistence(timeout: 5)); assertFixtureEnvironment(in: app, dynamicTypeSize: "large")
        tap("projectEdit.saveLocal", app, fixed: true); return app
    }
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.firstMatch; XCTAssertTrue(button.isEnabled && button.isHittable, app.debugDescription); button.tap()
    }
    private func insert(_ kind: String, before anchor: String?, _ app: XCUIApplication) {
        if let anchor {
            tap("projectStoryMedia.gap." + anchor, app)
            tap("projectStory" + kind + ".insertBefore." + anchor, app, fixed: true)
        } else { tap("projectStory" + kind + ".add", app) }
    }
    enum Gap: Equatable { case first, middle, end }
    func imageJourney(_ gap: Gap) throws {
        let app = launch("image"); var saved = try snapshot(app)
        let original = saved.savedDraft.chapters[0]
        let anchors: [String?] = [gap == .first ? original.blocks[0].id : gap == .middle ? original.blocks[1].id : nil]
        XCTAssertEqual(original.blocks.count, 2)
        for (number, anchor) in anchors.enumerated() {
            let before = saved.savedDraft.chapters[0].blocks, position = anchor.flatMap { id in before.firstIndex { $0.id == id } } ?? before.count
            tap("projectEdit.chapter." + original.id, app); insert("Image", before: anchor, app)
            tap("projectStoryImage.choose", app)
            if number == 0 { tap("template.imageCrop.cancel", app); XCTAssertFalse(app.buttons["projectStoryImage.upload"].exists); tap("projectStoryImage.choose", app) }
            tap("template.imageCrop.confirm", app); XCTAssertTrue(app.images["projectStoryImage.localPreview"].exists)
            tap("projectStoryImage.upload", app)
            let receipt = app.staticTexts["projectStoryImage.reference"], expected = "https://example.com/synthetic/story/e%CC%81.jpg?version=\(number + 1)"
            XCTAssertTrue(receipt.waitForExistence(timeout: 5)); XCTAssertEqual(Array(receipt.label.utf8), Array(expected.utf8))
            tap("projectStoryImage.apply", app); XCTAssertFalse(app.buttons["projectStoryImage.close"].exists); back(app)
            saved = try snapshot(app); let blocks = saved.savedDraft.chapters[0].blocks, added = blocks[position]
            XCTAssertEqual(added.kind, "image"); XCTAssertEqual(Array(added.url.utf8), Array(expected.utf8))
            XCTAssertEqual(blocks.filter { $0.id != added.id }, before); XCTAssertEqual(saved.storyImageUploadCount, number + 1)
            XCTAssertEqual(saved.storyAudioUploadCount, 0)
        }
        let ordered = saved.savedDraft.chapters[0].blocks
        tap("projectEdit.fixture.reopen", app, fixed: true); tap("projectEdit.restore", app); saved = try snapshot(app)
        XCTAssertEqual(saved.savedDraft.chapters[0].blocks, ordered); XCTAssertEqual(saved.storyImageUploadCount, 1)
        tap("projectEdit.review", app, fixed: true)
        for index in ordered.indices where ordered[index].kind == "image" {
            let prepared = app.staticTexts["projectStoryImage.prepared.0.\(index)"]
            XCTAssertTrue(revealFixtureElement(prepared, in: app, maximumSwipes: 45, requiresHittable: false), app.debugDescription)
            XCTAssertEqual(Array(prepared.label.utf8), Array(ordered[index].url.utf8))
        }
        tap("projectEdit.cancelReview", app); XCTAssertEqual(try snapshot(app).storyImageUploadCount, 1)
    }
    func audioJourney(_ gap: Gap) throws {
        let app = launch("audio"); var saved = try snapshot(app)
        let original = saved.savedDraft.chapters[0]
        let anchors: [String?] = [gap == .first ? original.blocks[0].id : gap == .middle ? original.blocks[1].id : nil]
        XCTAssertEqual(original.blocks.count, 2)
        for (number, anchor) in anchors.enumerated() {
            let before = saved.savedDraft.chapters[0].blocks, position = anchor.flatMap { id in before.firstIndex { $0.id == id } } ?? before.count
            tap("projectEdit.chapter." + original.id, app); insert("Audio", before: anchor, app)
            XCTAssertFalse(app.buttons["projectStoryAudio.choose"].exists); back(app); saved = try snapshot(app)
            let blank = saved.savedDraft.chapters[0].blocks[position]
            XCTAssertEqual(blank.kind, "audio"); XCTAssertEqual(blank.url, ""); XCTAssertEqual(saved.storyAudioUploadCount, number)
            XCTAssertEqual(saved.savedDraft.chapters[0].blocks.filter { $0.id != blank.id }, before)
            tap("projectEdit.chapter." + original.id, app); tap("projectStoryAudio.open." + blank.id, app)
            tap("projectStoryAudio.choose", app); XCTAssertTrue(app.staticTexts["projectStoryAudio.notUploaded"].exists)
            tap("projectStoryAudio.cancelLocal", app); XCTAssertFalse(app.buttons["projectStoryAudio.upload"].exists)
            tap("projectStoryAudio.close", app, fixed: true); back(app); saved = try snapshot(app)
            XCTAssertEqual(saved.savedDraft.chapters[0].blocks[position], blank); XCTAssertEqual(saved.storyAudioUploadCount, number)
            tap("projectEdit.chapter." + original.id, app); tap("projectStoryAudio.open." + blank.id, app)
            tap("projectStoryAudio.choose", app); tap("projectStoryAudio.upload", app)
            let receipt = app.staticTexts["projectStoryAudio.reference"], expected = "https://example.com/synthetic/story/e%CC%81.m4a?version=\(number + 1)"
            XCTAssertTrue(receipt.waitForExistence(timeout: 5)); XCTAssertEqual(Array(receipt.label.utf8), Array(expected.utf8))
            tap("projectStoryAudio.apply", app); XCTAssertFalse(app.buttons["projectStoryAudio.close"].exists); back(app); saved = try snapshot(app)
            let filled = saved.savedDraft.chapters[0].blocks[position]
            XCTAssertEqual(filled.id, blank.id); XCTAssertEqual(Array(filled.url.utf8), Array(expected.utf8))
            XCTAssertEqual(saved.savedDraft.chapters[0].blocks.filter { $0.id != blank.id }, before)
            XCTAssertEqual(saved.storyAudioUploadCount, number + 1); XCTAssertEqual(saved.storyImageUploadCount, 0)
        }
        let ordered = saved.savedDraft.chapters[0].blocks
        tap("projectEdit.fixture.reopen", app, fixed: true); tap("projectEdit.restore", app); saved = try snapshot(app)
        XCTAssertEqual(saved.savedDraft.chapters[0].blocks, ordered); XCTAssertEqual(saved.storyAudioUploadCount, 1)
        tap("projectEdit.review", app, fixed: true)
        for index in ordered.indices where ordered[index].kind == "audio" {
            let prepared = app.staticTexts["projectStoryAudio.prepared.0.\(index)"]
            XCTAssertTrue(revealFixtureElement(prepared, in: app, maximumSwipes: 45, requiresHittable: false), app.debugDescription)
            XCTAssertEqual(Array(prepared.label.utf8), Array(ordered[index].url.utf8))
        }
        tap("projectEdit.cancelReview", app); XCTAssertEqual(try snapshot(app).storyAudioUploadCount, 1)
    }
}
