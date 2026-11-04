import XCTest

/// Two bounded, single-launch synthetic journeys. Authored only; Apple execution is a separate gate.
/// Seed bytes enter only the existing DEBUG host. All editing, navigation, save, restore and review
/// use mounted controls. The snapshot observes coordinator state; it never supplies expected results.
@MainActor final class TemplateEditorControlsFlowTests: XCTestCase {
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

    // UNMEASURED full-method replacement estimate: 360 seconds. Includes pre-probe UI capture, stored-byte evidence and recovery editing.
    func testRuleRowsPreserveSourceUntilEditAndBoundASCIIThroughLocalRestore() throws {
        let rows = (1...11).map { "Rule \($0)" }
        let original = " \r\n" + rows.map { "  " + $0 + " \t" }.joined(separator: "\n\n") + "\n "
        let app = launch(rules: original, story: supportedStory)
        bytes(input("templateRules.input.0", in: app).value as? String, rows[0])
        bytes(try inspect(app).draft.ruleInstructions, original)
        tap("templateRules.add", in: app)
        let last = input("templateRules.input.11", in: app)
        let sixty = String(repeating: "a", count: 60)
        last.tap(); last.typeText(sixty)
        bytes(last.value as? String, sixty)
        let add = app.buttons["templateRules.add"]
        reveal(add, in: app, hittable: false); XCTAssertFalse(add.isEnabled)
        // Only the verified ASCII boundary is asserted. No non-ASCII length parity claim.
        reveal(last, in: app, towardTop: true); last.tap(); last.typeText("Z")
        let issue = app.staticTexts["templateRules.issue"]
        reveal(issue, in: app, hittable: false)
        XCTAssertEqual(issue.label, "Use 60 or fewer ASCII characters for this step. The previous text was kept.")
        // Capture the active control BEFORE tapping the probe, which can move keyboard focus.
        let visibleAfterRejection = input("templateRules.input.11", in: app, towardTop: true).value as? String
        let acceptedAfterRejection = try inspect(app)
        bytes(acceptedAfterRejection.draft.ruleInstructions, (rows + [sixty]).joined(separator: "\n"))
        bytes(visibleAfterRejection, sixty)
        bytes(input("templateRules.input.11", in: app, towardTop: true).value as? String, sixty)
        bytes(try inspect(app).draft.ruleInstructions, (rows + [sixty]).joined(separator: "\n"))
        let recoveredInput = input("templateRules.input.11", in: app, towardTop: true)
        recoveredInput.tap(); recoveredInput.typeText(XCUIKeyboardKey.delete.rawValue + "a")
        bytes(recoveredInput.value as? String, sixty)
        bytes(try inspect(app).draft.ruleInstructions, (rows + [sixty]).joined(separator: "\n"))
        tap("templateRules.remove.11", in: app, towardTop: true)
        reveal(add, in: app); XCTAssertTrue(add.isEnabled)
        let first = try insert("Edited ", into: "templateRules.input.0", in: app, towardTop: true)
        let expected = ([first.trimmingCharacters(in: .whitespacesAndNewlines)] + Array(rows.dropFirst())).joined(separator: "\n")
        bytes(try inspect(app).draft.ruleInstructions, expected)
        saveAndRestore(app)
        bytes(input("templateRules.input.0", in: app).value as? String, first.trimmingCharacters(in: .whitespacesAndNewlines))
        let restored = try inspect(app)
        bytes(restored.draft.ruleInstructions, expected)
        bytes(restored.draft.storyJson, supportedStory)
        bytes(restored.draft.storyText, legacySummary)
        assertHints(hints, draft: restored.draft)
        XCTAssertNil(restored.draft.storyTimelineEdited)
    }

    func testTimelineEditsDeriveCurrentSummaryAndSurviveExplicitRestore() throws {
        let app = launch(rules: "Retained rule", story: supportedStory)
        openStory(app)
        bytes(input("templateStory.beat.0.text", in: app).value as? String, "  First scene  ")
        let count = app.descendants(matching: .any)["templateStory.beat.0.imageCount"].firstMatch
        reveal(count, in: app, hittable: false)
        XCTAssertTrue(count.label.contains("6 / 6") || (count.value as? String) == "6 / 6")
        back(app)
        let untouched = try inspect(app)
        bytes(untouched.draft.storyJson, supportedStory); bytes(untouched.draft.storyText, legacySummary)
        XCTAssertNil(untouched.draft.storyTimelineEdited, "Viewing the timeline must not claim an edit")
        openStory(app)
        let images = try insert("edited-", into: "templateStory.beat.0.images", in: app)
        let second = try insert(" edited", into: "templateStory.beat.1.text", in: app)
        tap("templateAuthor.addBeat", in: app)
        let third = input("templateStory.beat.2.text", in: app)
        third.tap(); third.typeText("Third scene")
        let tag = input("templateStory.beat.2.tag", in: app, towardTop: true)
        tag.tap(); tag.typeText("End")
        back(app)
        let expectedSummary = "First scene\n" + second.trimmingCharacters(in: .whitespacesAndNewlines) + "\nThird scene"
        let summary = app.staticTexts["templateStory.summary"]
        reveal(summary, in: app, towardTop: true, hittable: false); bytes(summary.label, expectedSummary)
        let changed = try inspect(app)
        XCTAssertEqual(changed.draft.storyTimelineEdited, true)
        bytes(changed.draft.storyText, legacySummary, file: #filePath, line: #line)
        let json = try XCTUnwrap(changed.draft.storyJson)
        let beats = try JSONDecoder().decode([Beat].self, from: Data(json.utf8))
        XCTAssertEqual(beats.count, 3)
        XCTAssertEqual(beats[0].imgs, images.split(separator: "\n").map(String.init))
        XCTAssertEqual(beats[0].imgs.count, 6)
        bytes(beats[1].text, second); bytes(beats[2].text, "Third scene"); bytes(beats[2].tag, "End")
        XCTAssertTrue(beats[2].imgs.isEmpty)
        saveAndRestore(app)
        let restored = try inspect(app)
        bytes(restored.draft.storyJson, json); bytes(restored.draft.storyText, legacySummary)
        XCTAssertEqual(restored.draft.storyTimelineEdited, true)
        openStory(app)
        bytes(input("templateStory.beat.1.text", in: app).value as? String, second)
        bytes(input("templateStory.beat.2.text", in: app).value as? String, "Third scene")
        back(app)
        reveal(summary, in: app, towardTop: true, hittable: false); bytes(summary.label, expectedSummary)
        XCTAssertEqual(try inspect(app).state, "editing")
        openStory(app)
        bytes(input("templateStory.beat.2.text", in: app).value as? String, "Third scene")
        tap("templateAuthor.fixture.switch", in: app)
        // Observable scope-change behavior only; retained callback leases have separate unit tests.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.navigationBars["Story timeline"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["templateStory.beat.2.text"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Third scene"].exists)
        let switched = try inspect(app)
        XCTAssertNil(switched.draft.storyJson); XCTAssertNil(switched.draft.storyText)
    }


}
