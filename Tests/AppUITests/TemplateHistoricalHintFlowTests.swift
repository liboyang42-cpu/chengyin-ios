import XCTest

/// One bounded, single-launch synthetic journey. Authored only; Apple execution is a separate gate.
/// Seed bytes enter only the existing DEBUG host. All editing, navigation, save, restore and review
/// use mounted controls. The snapshot observes coordinator state; it never supplies expected results.
@MainActor final class TemplateHistoricalHintFlowTests: XCTestCase {
    private var application: XCUIApplication?
    private let legacySummary = "  Independent historical summary\r\n "
    private let hints = ["  First retained hint  ", "Second retained hint\t", "  Retained answer\n"]
    private let supportedStory = " \n" + #"[{"tag":"Start","text":"  First scene  ","imgs":["fixture:1","fixture:2","fixture:3","fixture:4","fixture:5","fixture:6"]},{"text":"Second scene","imgs":[],"tag":"Next"}]"# + "\n "
    private let historicalStory = " \r\n" + #"[{"tag":"Old","text":"Retained scene","imgs":[],"future":{"integer":9007199254740993,"decimal":1.2300}}]"# + "\t "
    private let localSaved = "Saved securely on this device for this account."
    private let simulated = "Simulation completed. No template was saved to a server or published."

    private struct Snapshot: Decodable {
        struct Draft: Decodable {
            let ruleInstructions: String?
            let storyJson: String?
            let storyText: String?
            let storyTimelineEdited: Bool?
            let validationMethod: Int
            let hint1: String?
            let hint2: String?
            let answerReveal: String?
            let legacyHintsEnabled: Bool?
        }
        let draft: Draft
        let requestCount: Int
        let inspectionSequence: Int
        let locked: Bool
        let state: String
    }
    private struct Beat: Decodable { let tag: String; let text: String; let imgs: [String] }

    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() {
        attachFailureScreenshot(self, app: application)
        application?.terminate(); application = nil
        super.tearDown()
    }

    private func launch(rules: String, story: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-template-authoring", "--template-author-local-probe",
                               "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["--template-author-rules-raw"] = rules
        app.launchEnvironment["--template-author-story-raw"] = story
        app.launchEnvironment["--template-author-story-text"] = legacySummary
        app.launchEnvironment["--template-author-hint1"] = hints[0]
        app.launchEnvironment["--template-author-hint2"] = hints[1]
        app.launchEnvironment["--template-author-answer-reveal"] = hints[2]
        application = app; app.launch()
        tap("templateAuthor.begin", in: app); tap("templateAuthor.continue", in: app)
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false,
                        hittable: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(revealFixtureElement(element, in: app, towardTop: towardTop, maximumSwipes: 40,
                                          requiresHittable: hittable), app.debugDescription, file: file, line: line)
    }
    private func tap(_ id: String, in app: XCUIApplication, towardTop: Bool = false,
                     file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id]
        if id.hasPrefix("templateAuthor.fixture.") || id == "templateAuthor.cancelReview" {
            XCTAssertTrue(button.waitForExistence(timeout: 5), id, file: file, line: line)
            XCTAssertTrue(button.isHittable, id, file: file, line: line)
        } else { reveal(button, in: app, towardTop: towardTop, file: file, line: line) }
        XCTAssertTrue(button.isEnabled, id, file: file, line: line); button.tap()
    }
    private func input(_ id: String, in app: XCUIApplication, towardTop: Bool = false,
                       editable: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        // SwiftUI's vertical TextField can be exposed as a text field or text view by iOS.
        let field = app.descendants(matching: .any)[id].firstMatch
        reveal(field, in: app, towardTop: towardTop, hittable: editable, file: file, line: line)
        XCTAssertEqual(field.isEnabled, editable, id, file: file, line: line)
        return field
    }
    private func bytes(_ actual: String?, _ expected: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(actual, file: file, line: line)
        // String equality alone permits Unicode normalization; stored source comparisons do not.
        XCTAssertEqual(actual.map { Array($0.utf8) }, Array(expected.utf8), file: file, line: line)
    }
    private func inspect(_ app: XCUIApplication, requests: Int = 0, locked: Bool = false) throws -> Snapshot {
        let probe = app.buttons["templateAuthor.fixture.localSnapshot"]
        let previous = (probe.value as? String) ?? ""
        tap("templateAuthor.fixture.localSnapshot", in: app)
        let refreshed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", previous, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 5), .completed, app.debugDescription)
        let text = try XCTUnwrap(probe.value as? String)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(text.utf8))
        XCTAssertGreaterThan(snapshot.inspectionSequence, 0)
        XCTAssertEqual(snapshot.requestCount, requests, "Only the explicit synthetic confirmation may dispatch")
        XCTAssertEqual(snapshot.locked, locked)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists,
                       "Local text editing must not activate providers or request device permissions")
        return snapshot
    }
    private func insert(_ addition: String, into id: String, in app: XCUIApplication,
                        towardTop: Bool = false) throws -> String {
        let field = input(id, in: app, towardTop: towardTop)
        let previous = try XCTUnwrap(field.value as? String)
        field.tap(); field.typeText(addition)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", previous), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        let current = try XCTUnwrap(field.value as? String)
        XCTAssertEqual(current.components(separatedBy: addition).count, 2)
        bytes(current.replacingOccurrences(of: addition, with: ""), previous)
        return current
    }
    private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.isHittable, app.debugDescription); back.tap()
    }
    private func openStory(_ app: XCUIApplication, towardTop: Bool = false) {
        tap("templateStory.open", in: app, towardTop: towardTop)
        XCTAssertTrue(app.navigationBars["Story timeline"].waitForExistence(timeout: 5))
    }
    private func saveAndRestore(_ app: XCUIApplication) {
        tap("templateAuthor.saveLocal", in: app)
        let status = app.staticTexts["templateAuthor.status"]
        reveal(status, in: app, hittable: false); XCTAssertEqual(status.label, localSaved)
        tap("templateAuthor.fixture.reopen", in: app)
        let restore = app.buttons["templateAuthor.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); XCTAssertTrue(restore.isEnabled)
        XCTAssertFalse(app.buttons["templateAuthor.saveLocal"].exists, "Reopen must not silently restore")
        tap("templateAuthor.restore", in: app)
    }
    private func choose(_ label: String, in app: XCUIApplication, towardTop: Bool = false) {
        let picker = app.descendants(matching: .any)["templateAuthor.method"].firstMatch
        reveal(picker, in: app, towardTop: towardTop); XCTAssertTrue(picker.isEnabled); picker.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(choice.isHittable); choice.tap()
    }
    private func hintsEnabled(_ enabled: Bool, in app: XCUIApplication, editable: Bool = true, towardTop: Bool = false) {
        let toggle = app.switches["templateLegacyHints.enabled"]
        reveal(toggle, in: app, towardTop: towardTop, hittable: editable)
        XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0")
        XCTAssertEqual(toggle.isEnabled, editable)
    }
    private func setHints(_ enabled: Bool, in app: XCUIApplication) {
        hintsEnabled(!enabled, in: app, towardTop: true)
        tapFixtureNativeSwitch(app.switches["templateLegacyHints.enabled"], in: app)
        hintsEnabled(enabled, in: app)
    }
    private func assertHints(_ expected: [String], draft: Snapshot.Draft) {
        bytes(draft.hint1, expected[0]); bytes(draft.hint2, expected[1]); bytes(draft.answerReveal, expected[2])
    }

    // Effective full-method estimate: 720 seconds, UNMEASURED. Prior estimates below are retained history.
    // UNMEASURED full-method replacement estimate: 540 seconds. Includes active-control capture and exact post-enable stored-byte evidence.
    func testHistoricalBytesHintOffRestoreAndSameOwnerLockedReadback() throws {
        let originalRules = " \n" + (1...13).map { "  Historical \($0)\t" }.joined(separator: "\r\n") + "\n "
        let app = launch(rules: originalRules, story: historicalStory)
        let original = app.staticTexts["templateRules.original"]
        reveal(original, in: app, hittable: false); bytes(original.label, originalRules)
        XCTAssertFalse(app.buttons["templateRules.add"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["templateRules.input.0"].firstMatch.exists)
        openStory(app)
        let unsupported = app.staticTexts["templateStory.issue"]
        XCTAssertTrue(unsupported.waitForExistence(timeout: 5))
        XCTAssertEqual(unsupported.label, "This story uses an unsupported or malformed format. Its original content is preserved and cannot be edited here.")
        XCTAssertFalse(app.buttons["templateAuthor.addBeat"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["templateStory.beat.0.text"].firstMatch.exists)
        back(app)
        let initial = try inspect(app)
        bytes(initial.draft.ruleInstructions, originalRules); bytes(initial.draft.storyJson, historicalStory)
        bytes(initial.draft.storyText, legacySummary); assertHints(hints, draft: initial.draft)
        XCTAssertNil(initial.draft.legacyHintsEnabled)
        hintsEnabled(true, in: app, towardTop: true)
        choose("Photo check-in", in: app, towardTop: true)
        XCTAssertFalse(app.switches["templateLegacyHints.enabled"].exists)
        let hidden = try inspect(app)
        XCTAssertEqual(hidden.draft.validationMethod, 2); XCTAssertEqual(hidden.draft.legacyHintsEnabled, false)
        assertHints(hints, draft: hidden.draft)
        choose("Text answer", in: app)
        hintsEnabled(false, in: app)
        setHints(true, in: app)
        let visibleAfterReenable = ["hint1", "hint2", "answerReveal"].map {
            input("templateAuthor.field." + $0, in: app).value as? String
        }
        let acceptedAfterReenable = try inspect(app)
        assertHints(hints, draft: acceptedAfterReenable.draft)
        for index in hints.indices { bytes(visibleAfterReenable[index], hints[index]) }
        for (index, field) in ["hint1", "hint2", "answerReveal"].enumerated() {
            bytes(input("templateAuthor.field." + field, in: app).value as? String, hints[index])
        }
        setHints(false, in: app)
        let cleared = try inspect(app)
        assertHints(["", "", ""], draft: cleared.draft)
        XCTAssertEqual(cleared.draft.legacyHintsEnabled, false)
        XCTAssertFalse(app.descendants(matching: .any)["templateAuthor.field.hint1"].firstMatch.exists)
        saveAndRestore(app)
        let restored = try inspect(app)
        bytes(restored.draft.ruleInstructions, originalRules); bytes(restored.draft.storyJson, historicalStory)
        bytes(restored.draft.storyText, legacySummary); assertHints(["", "", ""], draft: restored.draft)
        XCTAssertEqual(restored.draft.legacyHintsEnabled, false); XCTAssertNil(restored.draft.storyTimelineEdited)
        hintsEnabled(false, in: app)
        setHints(true, in: app)
        let fresh = ["Fresh first", "Fresh second", "Fresh reveal"]
        for (index, key) in ["hint1", "hint2", "answerReveal"].enumerated() {
            let field = input("templateAuthor.field." + key, in: app)
            field.tap(); field.typeText(fresh[index])
            bytes(field.value as? String, fresh[index])
        }
        assertHints(fresh, draft: try inspect(app).draft)
        tap("templateAuthor.reviewDraft", in: app)
        tap("templateAuthor.cancelReview", in: app)
        XCTAssertEqual(try inspect(app).state, "editing")
        tap("templateAuthor.reviewDraft", in: app)
        XCTAssertFalse(app.buttons["templateAuthor.confirmRequest"].exists)
        tap("templateAuthor.confirmSimulation", in: app)
        let status = app.staticTexts["templateAuthor.status"]
        reveal(status, in: app, hittable: false)
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", simulated), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 5), .completed, app.debugDescription)
        // This is the existing DEBUG-only simulated transport. No HTTP/provider/grant is activated.
        let locked = try inspect(app, requests: 1, locked: true)
        XCTAssertEqual(locked.state, "simulated"); assertHints(fresh, draft: locked.draft)
        bytes(locked.draft.ruleInstructions, originalRules); bytes(locked.draft.storyJson, historicalStory)
        hintsEnabled(true, in: app, editable: false, towardTop: true)
        for (index, key) in ["hint1", "hint2", "answerReveal"].enumerated() {
            bytes(input("templateAuthor.field." + key, in: app, editable: false).value as? String, fresh[index])
        }
        bytes(input("templateAuthor.field.storyText", in: app, editable: false).value as? String, legacySummary)
        let method = app.descendants(matching: .any)["templateAuthor.method"].firstMatch
        reveal(method, in: app, towardTop: true, hittable: false); XCTAssertFalse(method.isEnabled)
        reveal(original, in: app, towardTop: true, hittable: false); bytes(original.label, originalRules)
        for id in ["templateAuthor.saveLocal", "templateAuthor.reviewDraft", "templateAuthor.reviewPublish"] {
            let button = app.buttons[id]; reveal(button, in: app, hittable: false); XCTAssertFalse(button.isEnabled)
        }
        XCTAssertEqual(try inspect(app, requests: 1, locked: true).state, "simulated")
        tap("templateAuthor.fixture.signOut", in: app)
        XCTAssertTrue(app.staticTexts["templateAuthor.signIn"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["templateLegacyHints.enabled"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["templateAuthor.field.hint1"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["templateRules.original"].exists)
    }
}
