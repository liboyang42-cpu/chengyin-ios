import XCTest

/// Synthetic generated data only. Full-method UNMEASURED estimates: 240/420/660 seconds.
/// Actual Apple execution remains required; no files, microphones, uploads or live providers.
@MainActor final class TemplateMediaReviewFlowTests: XCTestCase {
    private var app: XCUIApplication?
    private struct Snapshot: Decodable {
        struct Draft: Decodable { let questionImg: String?; let questionAudio: String?; let audioUrl: String?; let storyJson: String?; let questionOptionMediaJson: String? }
        let draft: Draft
        let requestCount: Int
        let inspectionSequence: Int
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(synthetic: Bool) -> XCUIApplication {
        let value = XCUIApplication()
        value.launchArguments = ["--ui-template-authoring", "--template-author-local-probe", "--uitesting-reset-language",
                                 "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if synthetic { value.launchArguments += ["--template-author-media-fixture"] }
        app = value; value.launch(); tap("templateAuthor.begin", in: value); tap("templateAuthor.continue", in: value)
        return value
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false, hittable: Bool = true) {
        XCTAssertTrue(revealFixtureElement(element, in: app, towardTop: towardTop, maximumSwipes: 48, requiresHittable: hittable), app.debugDescription)
    }
    private func tap(_ id: String, in app: XCUIApplication, towardTop: Bool = false) {
        let button = app.buttons[id]
        if id == "templateMedia.cancel" || id.hasPrefix("templateAuthor.fixture.") {
            XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(button.isHittable, app.debugDescription)
        } else { reveal(button, in: app, towardTop: towardTop) }
        XCTAssertTrue(button.isEnabled, app.debugDescription); button.tap()
    }
    private func state(_ message: String, in app: XCUIApplication) {
        let label = app.staticTexts["templateMedia.state"]
        reveal(label, in: app, towardTop: true, hittable: false)
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", message), object: label)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(app.staticTexts["templateMedia.notUploaded"].exists)
    }
    private func gone(_ app: XCUIApplication) {
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["templateMedia.cancel"])
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 5), .completed, app.debugDescription)
    }
    private func inspect(_ app: XCUIApplication) throws -> Snapshot {
        let probe = app.buttons["templateAuthor.fixture.localSnapshot"], previous = (app.buttons["templateAuthor.fixture.localSnapshot"].value as? String) ?? ""
        tap("templateAuthor.fixture.localSnapshot", in: app)
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", previous, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 5), .completed, app.debugDescription)
        let value = try JSONDecoder().decode(Snapshot.self, from: Data(try XCTUnwrap(probe.value as? String).utf8))
        XCTAssertEqual(value.requestCount, 0); XCTAssertGreaterThan(value.inspectionSequence, 0)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        return value
    }
    private func unchanged(_ expected: Snapshot, in app: XCUIApplication) throws {
        let actual = try inspect(app)
        for (left, right) in [(actual.draft.questionImg, expected.draft.questionImg), (actual.draft.questionAudio, expected.draft.questionAudio),
                              (actual.draft.audioUrl, expected.draft.audioUrl), (actual.draft.storyJson, expected.draft.storyJson),
                              (actual.draft.questionOptionMediaJson, expected.draft.questionOptionMediaJson)] {
            XCTAssertEqual(left.map { Array($0.utf8) }, right.map { Array($0.utf8) })
        }
    }
    private func assertDestination(_ title: String, reference: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), app.debugDescription)
        let raw = app.staticTexts["templateMedia.savedReference"]
        reveal(raw, in: app, towardTop: true, hittable: false)
        XCTAssertEqual(Array(raw.label.utf8), Array(reference.utf8))
    }
    func testDefaultOffReviewCancelReopenAndFinishNeverOfferUploadOrApply() throws {
        let app = launch(synthetic: false), original = try inspect(app)
        tap("templateMedia.open.questionImage", in: app)
        state("No local selection yet.", in: app)
        let select = app.buttons["templateMedia.selectImage"]
        reveal(select, in: app, hittable: false); XCTAssertFalse(select.isEnabled)
        let apply = app.buttons["templateMedia.apply"]
        reveal(apply, in: app, hittable: false); XCTAssertFalse(apply.isEnabled)
        XCTAssertFalse(app.buttons["templateMedia.synthetic.ready"].exists)
        tap("templateMedia.cancel", in: app); gone(app)
        tap("templateMedia.open.questionImage", in: app)
        state("No local selection yet.", in: app); tap("templateMedia.finish", in: app); gone(app)
        try unchanged(original, in: app)
    }
    func testGeneratedImageCropReselectPendingCancelAndFailureKeepRawReferences() throws {
        let app = launch(synthetic: true), original = try inspect(app)
        tap("templateMedia.open.questionImage", in: app)
        let raw = app.staticTexts["templateMedia.savedReference"]
        reveal(raw, in: app, hittable: false)
        XCTAssertEqual(Array(raw.label.utf8), Array(try XCTUnwrap(original.draft.questionImg).utf8))
        tap("templateMedia.synthetic.ready", in: app)
        state("Review this local image crop. The source aspect ratio is retained.", in: app)
        let zoom = app.sliders["template.imageCrop.zoom"]
        reveal(zoom, in: app); zoom.adjust(toNormalizedSliderPosition: 0.4)
        tap("template.imageCrop.confirm", in: app)
        state("Ready for local review only. The saved reference is unchanged.", in: app)
        reveal(app.images["templateMedia.image"], in: app, hittable: false)
        XCTAssertTrue(app.images["templateMedia.image"].exists)
        tap("templateMedia.reselect", in: app)
        state("No local selection yet.", in: app); XCTAssertFalse(app.images["templateMedia.image"].exists)
        tap("templateMedia.synthetic.held", in: app)
        state("Local selection is pending. Nothing has been uploaded.", in: app)
        tap("templateMedia.cancel", in: app); gone(app)
        tap("templateMedia.open.questionImage", in: app)
        tap("templateMedia.synthetic.failed", in: app)
        state("The local selection could not be inspected. Reselect or cancel.", in: app)
        tap("templateMedia.reselect", in: app); tap("templateMedia.synthetic.ready", in: app)
        tap("template.imageCrop.cancel", in: app, towardTop: true)
        state("No local selection yet.", in: app); tap("templateMedia.finish", in: app); gone(app)
        try unchanged(original, in: app)
    }
    func testAudioMetadataAndStoryLocalReviewReturnWithoutAttachingAnything() throws {
        let app = launch(synthetic: true), original = try inspect(app)
        tap("templateMedia.open.questionAudio", in: app)
        tap("templateMedia.synthetic.held", in: app); tap("templateMedia.synthetic.complete", in: app)
        state("Ready for local review only. The saved reference is unchanged.", in: app)
        let metadata = app.staticTexts["templateMedia.audioMetadata"]
        reveal(metadata, in: app, hittable: false); XCTAssertEqual(metadata.label, "m4a · 128")
        XCTAssertFalse(app.images["templateMedia.image"].exists)
        tap("templateMedia.finish", in: app); gone(app)
        // Use the ordinary method selector; distinct options expose row-dispatch mistakes.
        let picker = app.descendants(matching: .any)["templateAuthor.method"].firstMatch
        reveal(picker, in: app, towardTop: true); XCTAssertTrue(picker.isEnabled); picker.tap()
        let choice = app.buttons["Multiple choice"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); XCTAssertTrue(choice.isHittable); choice.tap()
        tap("templateMedia.open.optionImage.A", in: app)
        assertDestination("Choice image A", reference: "  fixture:option-A-e\u{301}\r\n", in: app)
        tap("templateMedia.synthetic.ready", in: app)
        tap("template.imageCrop.cancel", in: app, towardTop: true)
        tap("templateMedia.finish", in: app); gone(app)
        tap("templateMedia.open.optionAudio.B", in: app)
        assertDestination("Choice audio B", reference: "\tfixture:option-B-audio ", in: app)
        tap("templateMedia.synthetic.ready", in: app)
        state("Ready for local review only. The saved reference is unchanged.", in: app)
        tap("templateMedia.finish", in: app); gone(app)
        tap("templateMedia.open.narration", in: app)
        assertDestination("Audio reference", reference: try XCTUnwrap(original.draft.audioUrl), in: app)
        tap("templateMedia.synthetic.ready", in: app)
        state("Ready for local review only. The saved reference is unchanged.", in: app)
        tap("templateMedia.finish", in: app); gone(app)
        tap("templateStory.open", in: app, towardTop: true)
        tap("templateMedia.open.beat.0.storyImage.0", in: app)
        tap("templateMedia.synthetic.ready", in: app)
        tap("template.imageCrop.confirm", in: app, towardTop: true)
        state("Ready for local review only. The saved reference is unchanged.", in: app)
        tap("templateMedia.finish", in: app); gone(app)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.isHittable); back.tap()
        try unchanged(original, in: app)
        tap("templateAuthor.fixture.switch", in: app)
        XCTAssertFalse(app.buttons["templateMedia.cancel"].exists)
        XCTAssertFalse(app.images["templateMedia.image"].exists)
        XCTAssertEqual(try inspect(app).requestCount, 0)
    }
}
