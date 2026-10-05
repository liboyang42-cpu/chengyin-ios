import XCTest

/// Synthetic local-authoring acceptance. Apple compilation and simulator execution are separate gates.
/// The fixture seeds only source bytes; entry, method selection, validation, edits and restore use the real UI.
@MainActor final class TemplatePreferenceDraftEditorFlowTests: XCTestCase {
    private var launchedApp: XCUIApplication?
    // Preserve whitespace, an unknown object, large integer spelling and decimal trailing zeroes.
    // A single dimension deliberately keeps the real preview small and the shard work bounded.
    private let original = " \n" + #"""
    {
      "future" : {"integer":9007199254740993,"decimal":1.2300},
      "dimensions" : ["space"],
      "steps" : [{"key":"q","type":"single","title":"Synthetic current question","options":[
        {"key":"A","text":"First option","scores":{"space":1}},
        {"key":"B","text":"Second option","scores":{"space":2}}
      ]}],
      "results" : {"space":{"title":"Synthetic current result","body":"Because {{choices}}","nextStep":"Try one action","nextStepDays":7}}
    }
    """# + "\n "
    private let validMessage = "Supported preference rules passed locally. This does not enable publishing."

    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() {
        attachFailureScreenshot(self, app: launchedApp)
        launchedApp?.terminate(); launchedApp = nil
        super.tearDown()
    }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-template-authoring", "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["--template-author-preference-raw"] = original
        launchedApp = app; app.launch()
        tap("templateAuthor.begin", in: app)
        tap("templateAuthor.continue", in: app)
        // The source is not mounted by a vm6-only test screen or automatic method selection.
        XCTAssertFalse(app.textViews["templateAuthor.preference.source"].exists)
        chooseMethod("Preference questionnaire (local)", in: app)
        assertSource(original, in: app)
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false,
                        requiresHittable: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(revealFixtureElement(element, in: app, towardTop: towardTop, maximumSwipes: 35,
                                          requiresHittable: requiresHittable), app.debugDescription, file: file, line: line)
    }
    private func tap(_ identifier: String, in app: XCUIApplication,
                     file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        if identifier.hasPrefix("templateAuthor.fixture.") {
            XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
            XCTAssertTrue(button.isHittable, file: file, line: line)
        } else { reveal(button, in: app, file: file, line: line) }
        XCTAssertTrue(button.isEnabled, file: file, line: line)
        button.tap()
    }
    private func chooseMethod(_ label: String, in app: XCUIApplication, towardTop: Bool = false,
                              file: StaticString = #filePath, line: UInt = #line) {
        // Native menu pickers vary between Button and PopUpButton across iOS releases.
        let picker = app.descendants(matching: .any)["templateAuthor.method"].firstMatch
        reveal(picker, in: app, towardTop: towardTop, file: file, line: line)
        XCTAssertTrue(picker.isEnabled, file: file, line: line); picker.tap()
        let option = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        XCTAssertTrue(option.isHittable, app.debugDescription, file: file, line: line)
        option.tap()
    }
    private func assertBytes(_ actual: String?, equal expected: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        // Swift String equality normalizes Unicode; UTF-8 comparison catches source rewriting.
        XCTAssertNotNil(actual, file: file, line: line)
        XCTAssertEqual(actual.map { Array($0.utf8) }, Array(expected.utf8), file: file, line: line)
    }
    private func assertSource(_ expected: String, in app: XCUIApplication, towardTop: Bool = false,
                              file: StaticString = #filePath, line: UInt = #line) {
        let source = app.textViews["templateAuthor.preference.source"]
        reveal(source, in: app, towardTop: towardTop, file: file, line: line)
        assertBytes(source.value as? String, equal: expected, file: file, line: line)
    }
    private func check(_ message: String, in app: XCUIApplication,
                       file: StaticString = #filePath, line: UInt = #line) {
        tap("templateAuthor.preference.check", in: app, file: file, line: line)
        let status = app.staticTexts["templateAuthor.preference.status"]
        reveal(status, in: app, requiresHittable: false, file: file, line: line)
        let current = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", message), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [current], timeout: 5), .completed, app.debugDescription, file: file, line: line)
        XCTAssertEqual(status.label, message, file: file, line: line)
        XCTAssertTrue(app.buttons["templateAuthor.preference.check"].isEnabled, file: file, line: line)
    }
    private func assertUnchecked(in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let unchecked = app.staticTexts["templateAuthor.preference.unchecked"]
        reveal(unchecked, in: app, requiresHittable: false, file: file, line: line)
        XCTAssertTrue(unchecked.exists, file: file, line: line)
        // The previous status and the preview heading share this same nearby viewport.
        XCTAssertFalse(app.staticTexts["templateAuthor.preference.status"].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts["templateAuthor.preference.preview"].exists, file: file, line: line)
    }

    func testNormalMethodEntryPreservesOriginalJSONAndKeepsRemoteActionsDisabled() {
        let app = launch()
        assertUnchecked(in: app)
        check(validMessage, in: app)
        let preview = app.staticTexts["templateAuthor.preference.preview"]
        reveal(preview, in: app, requiresHittable: false)
        let dimension = app.staticTexts["templateAuthor.preference.field.$.dimensions[0]"]
        reveal(dimension, in: app, requiresHittable: false)
        XCTAssertEqual(dimension.label, "space")
        assertSource(original, in: app, towardTop: true)
        for identifier in ["templateAuthor.preview", "templateAuthor.reviewDraft", "templateAuthor.reviewPublish"] {
            let button = app.buttons[identifier]
            reveal(button, in: app, requiresHittable: false)
            XCTAssertFalse(button.isEnabled, identifier)
        }
        XCTAssertFalse(app.buttons["templateAuthor.confirmSimulation"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.confirmRequest"].exists)
    }

    func testInvalidCurrentTextClearsOldPreviewAndSurvivesExplicitSaveRestore() {
        let app = launch()
        check(validMessage, in: app)
        reveal(app.staticTexts["templateAuthor.preference.preview"], in: app, requiresHittable: false)
        let source = app.textViews["templateAuthor.preference.source"]
        reveal(source, in: app, towardTop: true)
        // An actual newline plus a bare token is invalid at every insertion point in this JSON.
        // Do not depend on an undocumented caret position or replace the source through a fixture.
        let insertion = "\nINVALID_CURRENT\n"
        source.tap(); source.typeText(insertion)
        guard let current = source.value as? String else { return XCTFail("Missing edited source") }
        XCTAssertEqual(current.components(separatedBy: insertion).count, 2)
        assertBytes(current.replacingOccurrences(of: insertion, with: ""), equal: original)
        assertUnchecked(in: app)
        check("Invalid JSON. Your current text is retained.", in: app)
        XCTAssertFalse(app.staticTexts["templateAuthor.preference.preview"].exists)
        XCTAssertFalse(app.staticTexts["templateAuthor.preference.field.$.dimensions[0]"].exists)
        assertSource(current, in: app, towardTop: true)
        tap("templateAuthor.saveLocal", in: app)
        let saved = app.staticTexts["templateAuthor.status"]
        reveal(saved, in: app, requiresHittable: false)
        XCTAssertEqual(saved.label, "Saved securely on this device for this account.")
        tap("templateAuthor.fixture.reopen", in: app)
        XCTAssertTrue(app.buttons["templateAuthor.restore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["templateAuthor.preference.source"].exists)
        tap("templateAuthor.restore", in: app)
        assertSource(current, in: app)
        assertUnchecked(in: app)
        check("Invalid JSON. Your current text is retained.", in: app)
        XCTAssertFalse(app.staticTexts["templateAuthor.preference.preview"].exists)
    }

    func testSwitchingMethodCancelsPriorPreviewAndRequiresFreshValidation() {
        let app = launch()
        check(validMessage, in: app)
        reveal(app.staticTexts["templateAuthor.preference.preview"], in: app, requiresHittable: false)
        chooseMethod("No validation", in: app, towardTop: true)
        XCTAssertFalse(app.textViews["templateAuthor.preference.source"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.preference.check"].exists)
        XCTAssertFalse(app.staticTexts["templateAuthor.preference.status"].exists)
        XCTAssertFalse(app.staticTexts["templateAuthor.preference.preview"].exists)
        chooseMethod("Preference questionnaire (local)", in: app)
        assertSource(original, in: app)
        assertUnchecked(in: app)
        check(validMessage, in: app)
        let dimension = app.staticTexts["templateAuthor.preference.field.$.dimensions[0]"]
        reveal(dimension, in: app, requiresHittable: false)
        XCTAssertEqual(dimension.label, "space")
        assertSource(original, in: app, towardTop: true)
    }
}
