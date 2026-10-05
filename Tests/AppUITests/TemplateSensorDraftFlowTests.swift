import XCTest

/// Authored, synthetic local-configuration acceptance. Apple execution is separate.
/// No permission handler, sensor provider, recording or real transport is mounted.
@MainActor final class TemplateSensorDraftFlowTests: XCTestCase {
    private var application: XCUIApplication?
    private let validStatus = "Configuration values are valid. Device behavior has not been tested."
    private let invalidStatus = "Current input is incomplete or invalid. You can still save it locally."
    private let preserved = "This saved configuration is unsupported or ambiguous. Its original contents are preserved read-only."
    private let source = " {\r\n\t\"windowSec\" : 60, \"targetSteps\" : 12\r\n} \t"

    private struct Snapshot: Decodable {
        struct Draft: Decodable {
            struct Sensor: Decodable {
                struct Working: Decodable { let type: String?; let inputs: [String: String] }
                let originalType: String?
                let originalConfig: String?
                let working: Working?
            }
            let validationMethod: Int
            let sensorDraft: Sensor?
        }
        let draft: Draft
        let requestCount: Int
    }

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: application)
        application?.terminate(); application = nil
    }

    private func launch(type: String, raw: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-template-authoring", "--template-author-local-probe",
                               "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["--template-author-sensor-type"] = type
        app.launchEnvironment["--template-author-sensor-raw"] = raw
        application = app; app.launch()
        tap("templateAuthor.begin", in: app); tap("templateAuthor.continue", in: app)
        // Exercise the real vm7 selection. The fixture deliberately starts at vm1.
        // Native menu pickers expose Button or PopUpButton depending on iOS.
        let picker = app.descendants(matching: .any)["templateAuthor.method"].firstMatch
        XCTAssertTrue(revealFixtureElement(picker, in: app, maximumSwipes: 36), app.debugDescription)
        XCTAssertTrue(picker.isEnabled); picker.tap()
        let choice = app.buttons["Sensor challenge (local)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(choice.isHittable); choice.tap()
        return app
    }

    private func tap(_ id: String, in app: XCUIApplication, towardTop: Bool = false) {
        let button = app.buttons[id]
        if id.hasPrefix("templateAuthor.fixture.") {
            XCTAssertTrue(button.waitForExistence(timeout: 5), id)
            XCTAssertTrue(button.isHittable, id)
        } else {
            XCTAssertTrue(revealFixtureElement(button, in: app, towardTop: towardTop, maximumSwipes: 36), id + "\n" + app.debugDescription)
        }
        XCTAssertTrue(button.isEnabled, id); button.tap()
    }

    private func field(_ parameter: String, in app: XCUIApplication, towardTop: Bool = false) -> XCUIElement {
        let field = app.textFields["sensorDraft.input." + parameter]
        XCTAssertTrue(revealFixtureElement(field, in: app, towardTop: towardTop, maximumSwipes: 36), app.debugDescription)
        return field
    }

    private func insert(_ text: String, into parameter: String, in app: XCUIApplication) throws -> String {
        let input = field(parameter, in: app)
        let previous = try XCTUnwrap(input.value as? String)
        input.tap(); input.typeText(text)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", previous), object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
        let current = try XCTUnwrap(input.value as? String)
        XCTAssertEqual(current.components(separatedBy: text).count, 2)
        XCTAssertEqual(current.replacingOccurrences(of: text, with: ""), previous)
        return current
    }

    private func inspect(_ app: XCUIApplication, type: String, raw: String) throws -> Snapshot.Draft.Sensor {
        let probe = app.buttons["templateAuthor.fixture.localSnapshot"]
        let previous = (probe.value as? String) ?? ""
        tap("templateAuthor.fixture.localSnapshot", in: app)
        // The probe's increasing inspection sequence prevents accepting an old snapshot.
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", previous, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 5), .completed, app.debugDescription)
        let json = try XCTUnwrap(probe.value as? String)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.draft.validationMethod, 7)
        XCTAssertEqual(snapshot.requestCount, 0, "Local editing must not dispatch even to the synthetic transport")
        let sensor = try XCTUnwrap(snapshot.draft.sensorDraft)
        XCTAssertEqual(sensor.originalType, type)
        let original = try XCTUnwrap(sensor.originalConfig)
        XCTAssertEqual(Array(original.utf8), Array(raw.utf8), "Original JSON must remain byte-exact, including whitespace and key order")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists,
                       "Configuration editing must not trigger a device permission prompt")
        return sensor
    }

    private func preview(_ app: XCUIApplication, target: String, status: String) {
        tap("sensorDraft.preview", in: app)
        let statusLabel = app.staticTexts["sensorDraft.preview.status"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(statusLabel.label, status)
        XCTAssertEqual(app.descendants(matching: .any)["sensorDraft.preview.value.targetSteps"].firstMatch.value as? String, target)
        XCTAssertEqual(app.descendants(matching: .any)["sensorDraft.preview.value.windowSec"].firstMatch.value as? String, "60")
        XCTAssertEqual(app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sensorDraft.input.")).count, 0)
    }

    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(button.isHittable, app.debugDescription); button.tap()
    }

    private func assertRemoteActionsDisabled(_ app: XCUIApplication) {
        for id in ["templateAuthor.reviewDraft", "templateAuthor.reviewPublish"] {
            let button = app.buttons[id]
            XCTAssertTrue(revealFixtureElement(button, in: app, maximumSwipes: 36, requiresHittable: false), id)
            XCTAssertFalse(button.isEnabled, id)
        }
        XCTAssertFalse(app.buttons["templateAuthor.confirmRequest"].exists)
        XCTAssertFalse(app.buttons["templateAuthor.confirmSimulation"].exists)
    }

    func testCurrentSensorPreviewAndRestorePreserveExactOriginalJSON() throws {
        let app = launch(type: "steps", raw: source)
        XCTAssertEqual(field("targetSteps", in: app).value as? String, "12")
        XCTAssertEqual(field("windowSec", in: app).value as? String, "60")
        XCTAssertNil(try inspect(app, type: "steps", raw: source).working)
        // Inserting one digit is valid at every caret position; the test observes
        // the exact UI result rather than assuming where native TextField tapped.
        let validCurrent = try insert("3", into: "targetSteps", in: app)
        XCTAssertTrue((1...100_000).contains(try XCTUnwrap(Int(validCurrent))))
        preview(app, target: validCurrent, status: validStatus)
        XCTAssertEqual(try inspect(app, type: "steps", raw: source).working?.inputs["targetSteps"], validCurrent)
        back(app)
        // Six nonzero digits make the current value out of range at any caret
        // position, without relying on a select-all menu or fixture mutation.
        let invalidCurrent = try insert("999999", into: "targetSteps", in: app)
        XCTAssertGreaterThan(try XCTUnwrap(Int(invalidCurrent)), 100_000)
        preview(app, target: invalidCurrent, status: invalidStatus)
        XCTAssertFalse(app.staticTexts[validStatus].exists, "Invalid current input must never fall back to valid original JSON")
        back(app)
        assertRemoteActionsDisabled(app)
        tap("templateAuthor.saveLocal", in: app, towardTop: true)
        let saved = app.staticTexts["templateAuthor.status"]
        XCTAssertTrue(revealFixtureElement(saved, in: app, maximumSwipes: 10, requiresHittable: false))
        XCTAssertEqual(saved.label, "Saved securely on this device for this account.")
        XCTAssertEqual(try inspect(app, type: "steps", raw: source).working?.inputs["targetSteps"], invalidCurrent)
        tap("templateAuthor.fixture.reopen", in: app)
        XCTAssertTrue(app.buttons["templateAuthor.restore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["sensorDraft.input.targetSteps"].exists, "Restore must remain explicit")
        tap("templateAuthor.restore", in: app)
        XCTAssertEqual(field("targetSteps", in: app).value as? String, invalidCurrent)
        let restored = try inspect(app, type: "steps", raw: source)
        XCTAssertEqual(restored.working?.type, "steps")
        XCTAssertEqual(restored.working?.inputs, ["targetSteps": invalidCurrent, "windowSec": "60"])
        preview(app, target: invalidCurrent, status: invalidStatus)
        back(app)
        // Reopening the child preview cannot resurrect its prior valid result.
        preview(app, target: invalidCurrent, status: invalidStatus)
    }

    func testHistoricalUnknownAndAmbiguousConfigurationsRemainReadOnly() throws {
        let historical = [
            ("future_sensor", " {\r\n\"future\" : [1,true]\r\n} "),
            ("steps", " {\"targetSteps\":12, \"windowSec\":60, \"future\":true} ")
        ]
        for (type, raw) in historical {
            let app = launch(type: type, raw: raw)
            let notice = app.staticTexts["sensorDraft.preserved"]
            XCTAssertTrue(revealFixtureElement(notice, in: app, maximumSwipes: 10, requiresHittable: false))
            XCTAssertEqual(notice.label, preserved)
            XCTAssertFalse(app.descendants(matching: .any)["sensorDraft.type"].firstMatch.exists)
            XCTAssertEqual(app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sensorDraft.input.")).count, 0)
            XCTAssertNil(try inspect(app, type: type, raw: raw).working)
            tap("sensorDraft.preview", in: app)
            XCTAssertTrue(app.staticTexts["sensorDraft.preview.preserved"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["sensorDraft.preview.preserved"].label, preserved)
            XCTAssertFalse(app.staticTexts["sensorDraft.preview.status"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["sensorDraft.preview.value.targetSteps"].firstMatch.exists)
            back(app)
            assertRemoteActionsDisabled(app)
            tap("templateAuthor.saveLocal", in: app, towardTop: true)
            tap("templateAuthor.fixture.reopen", in: app)
            XCTAssertTrue(app.buttons["templateAuthor.restore"].waitForExistence(timeout: 5))
            tap("templateAuthor.restore", in: app)
            XCTAssertTrue(revealFixtureElement(notice, in: app, maximumSwipes: 36, requiresHittable: false))
            XCTAssertFalse(app.descendants(matching: .any)["sensorDraft.type"].firstMatch.exists)
            XCTAssertEqual(app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sensorDraft.input.")).count, 0)
            XCTAssertNil(try inspect(app, type: type, raw: raw).working)
            app.terminate(); application = nil
        }
    }
}
