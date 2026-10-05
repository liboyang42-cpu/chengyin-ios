import XCTest

/// Reconstructed synthetic UI coverage, not recovery of the former patch or runtime acceptance.
/// Three single-launch journeys. UNMEASURED planning estimates: 240 + 360 + 420 = 1,020 seconds.
/// The DEBUG probe observes the coordinator, reader and synthetic transport after ordinary controls.
@MainActor final class TemplateMetadataSelectorsFlowTests: XCTestCase {
    private var application: XCUIApplication?
    private let exactPlayers = "  team:2-6  "
    private let originalCSV = " 999, 11,12 "
    private let selectedCSV = "999,11,12,103,101,102,104,105,106,107,108,109,110,111,112,113"
    private let playersRead = "app_template_players"
    private let durationRead = "app_template_duration"
    private let categoriesRead = "categories:4"

    private struct Snapshot: Decodable {
        struct Draft: Decodable {
            let title: String
            let players: String?
            let duration: Int?
            let activityCategoryids: String?
            let categoryId: Int?
        }
        struct RequestFields: Decodable {
            let title: String
            let players: String?
            let duration: Int?
            let activityCategoryids: String?
            let categoryId: Int?
        }
        let draft: Draft
        let requestCount: Int
        let inspectionSequence: Int
        let locked: Bool
        let state: String
        let accountID: Int?
        let metadataReadInvocations: [String]
        let metadataReadCompletions: [String]
        let metadataPendingReadCount: Int
        let lastRequestPath: String?
        let lastRequestFields: RequestFields?
    }

    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() {
        attachFailureScreenshot(self, app: application)
        application?.terminate(); application = nil
        super.tearDown()
    }
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-template-authoring", "--template-author-local-probe",
                               "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["--template-author-metadata-scenario"] = scenario
        application = app; app.launch()
        tap("templateAuthor.begin", in: app); tap("templateAuthor.continue", in: app)
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false,
                        hittable: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        // Reveal FIRST: lazy rows may not exist in the accessibility tree until scrolled into view.
        XCTAssertTrue(revealFixtureElement(element, in: app, towardTop: towardTop, maximumSwipes: 50,
                                          requiresHittable: hittable), app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.exists, file: file, line: line)
    }
    private func tap(_ id: String, in app: XCUIApplication, towardTop: Bool = false,
                     file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id]
        if id.hasPrefix("templateAuthor.fixture.") || id == "templateAuthor.cancelReview" ||
            id == "templateMetadata.cancel" || id == "templateMetadata.save" {
            XCTAssertTrue(button.waitForExistence(timeout: 5), id, file: file, line: line)
            XCTAssertTrue(button.isHittable, id, file: file, line: line)
        } else { reveal(button, in: app, towardTop: towardTop, file: file, line: line) }
        XCTAssertTrue(button.isEnabled, id, file: file, line: line); button.tap()
    }
    private func bytes(_ actual: String?, _ expected: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.map { Array($0.utf8) }, Array(expected.utf8), file: file, line: line)
    }
    private func gone(_ element: XCUIElement, in app: XCUIApplication) {
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 5), .completed, app.debugDescription)
    }
    private func open(_ field: String, in app: XCUIApplication) {
        tap("templateMetadata.open." + field, in: app, towardTop: true)
        XCTAssertTrue(app.buttons["templateMetadata.cancel"].waitForExistence(timeout: 5), app.debugDescription)
    }
    private func close(_ app: XCUIApplication, save: Bool = false) {
        tap(save ? "templateMetadata.save" : "templateMetadata.cancel", in: app)
        gone(app.buttons["templateMetadata.cancel"], in: app)
    }
    private func option(_ index: Int, in app: XCUIApplication, enabled: Bool = true,
                        towardTop: Bool = false) -> XCUIElement {
        let row = app.buttons["templateMetadata.option.\(index)"]
        reveal(row, in: app, towardTop: towardTop, hittable: enabled)
        XCTAssertEqual(row.isEnabled, enabled)
        return row
    }
    private func choose(_ index: Int, in app: XCUIApplication, towardTop: Bool = false) {
        option(index, in: app, towardTop: towardTop).tap()
        gone(app.buttons["templateMetadata.cancel"], in: app)
    }
    private func category(_ id: Int, in app: XCUIApplication, selected: Bool,
                          towardTop: Bool = false) -> XCUIElement {
        let row = app.buttons["templateMetadata.category.\(id)"]
        reveal(row, in: app, towardTop: towardTop)
        XCTAssertTrue(row.isEnabled)
        // Known rows have the production .isSelected accessibility trait.
        if id != 999 { XCTAssertEqual(row.isSelected, selected, "Category \(id)") }
        return row
    }
    private func toggle(_ id: Int, in app: XCUIApplication, from selected: Bool = false,
                        towardTop: Bool = false) {
        let row = category(id, in: app, selected: selected, towardTop: towardTop)
        row.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == %@", NSNumber(value: !selected)), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, app.debugDescription)
    }
    private func saved(_ expected: String, in app: XCUIApplication) {
        let raw = app.staticTexts["templateMetadata.savedRaw"]
        reveal(raw, in: app, towardTop: true, hittable: false); bytes(raw.label, expected)
    }
    private func inspect(_ app: XCUIApplication, requests: Int = 0, locked: Bool = false) throws -> Snapshot {
        let probe = app.buttons["templateAuthor.fixture.localSnapshot"]
        let previous = (probe.value as? String) ?? ""
        tap("templateAuthor.fixture.localSnapshot", in: app)
        let refreshed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@ AND value BEGINSWITH %@", previous, "{"), object: probe)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 5), .completed, app.debugDescription)
        let text = try XCTUnwrap(probe.value as? String)
        let value = try JSONDecoder().decode(Snapshot.self, from: Data(text.utf8))
        XCTAssertGreaterThan(value.inspectionSequence, 0)
        XCTAssertEqual(value.requestCount, requests, "Metadata reads must never increment the synthetic writer count")
        XCTAssertEqual(value.locked, locked)
        if requests == 0 { XCTAssertNil(value.lastRequestPath); XCTAssertNil(value.lastRequestFields) }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists,
                       "Synthetic metadata must not request provider permissions")
        return value
    }
    private func reads(_ value: Snapshot, _ expected: [String], pending: Int = 0) {
        XCTAssertEqual(value.metadataReadInvocations, expected)
        XCTAssertEqual(value.metadataPendingReadCount, pending)
        XCTAssertEqual(value.metadataReadCompletions, pending == 0 ? expected : Array(expected.dropLast()))
    }
    private func saveAndRestore(_ app: XCUIApplication) throws {
        tap("templateAuthor.saveLocal", in: app)
        let status = app.staticTexts["templateAuthor.status"]
        reveal(status, in: app, hittable: false)
        XCTAssertEqual(status.label, "Saved securely on this device for this account.")
        tap("templateAuthor.fixture.reopen", in: app)
        let restore = app.buttons["templateAuthor.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); XCTAssertTrue(restore.isEnabled)
        XCTAssertFalse(app.buttons["templateMetadata.open.players"].exists, "Reopen requires explicit Restore")
        _ = try inspect(app)
        tap("templateAuthor.restore", in: app)
    }
    private func confirmDraft(_ app: XCUIApplication) throws -> Snapshot {
        tap("templateAuthor.reviewDraft", in: app)
        XCTAssertFalse(app.buttons["templateAuthor.confirmRequest"].exists)
        tap("templateAuthor.confirmSimulation", in: app)
        gone(app.buttons["templateAuthor.cancelReview"], in: app)
        let status = app.staticTexts["templateAuthor.status"]
        reveal(status, in: app, hittable: false)
        let simulated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@",
            "Simulation completed. No template was saved to a server or published."), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [simulated], timeout: 5), .completed, app.debugDescription)
        let result = try inspect(app, requests: 1, locked: true)
        XCTAssertEqual(result.state, "simulated"); XCTAssertEqual(result.lastRequestPath, "/api/template/draft")
        return result
    }
    private func lockedValue(_ field: String, _ expected: String, in app: XCUIApplication,
                             towardTop: Bool = false) {
        let row = app.buttons["templateMetadata.open." + field]
        reveal(row, in: app, towardTop: towardTop, hittable: false)
        XCTAssertFalse(row.isEnabled)
        XCTAssertTrue(row.label.contains(expected) || (row.value as? String)?.contains(expected) == true,
                      "Same-owner locked selector must still display its value: " + row.debugDescription)
    }

    // UNMEASURED estimate: 240 seconds. Exact dictValue semantics, unsupported durations and real confirmation.
    func testExactDictionaryValuesCancelRestoreAndSyntheticRequest() throws {
        let app = launch("dictionary")
        let initial = try inspect(app)
        XCTAssertNil(initial.draft.players); XCTAssertNil(initial.draft.duration); XCTAssertNil(initial.draft.activityCategoryids)
        reads(initial, [])
        open("players", in: app)
        XCTAssertTrue(option(0, in: app).label.contains("A friendly group"))
        XCTAssertFalse(app.staticTexts["templateMetadata.savedRaw"].exists)
        close(app)
        let canceled = try inspect(app)
        XCTAssertNil(canceled.draft.players); XCTAssertNil(canceled.draft.duration)
        reads(canceled, [playersRead])
        open("players", in: app); choose(0, in: app)
        bytes(try inspect(app).draft.players, exactPlayers)
        open("duration", in: app)
        for (index, spelling) in ["045", "+45", "45.0", "2147483648"].enumerated() {
            let row = option(index + 1, in: app, enabled: false)
            XCTAssertTrue(row.label.contains(spelling), row.debugDescription)
        }
        close(app)
        let unsupported = try inspect(app)
        XCTAssertNil(unsupported.draft.duration); bytes(unsupported.draft.players, exactPlayers)
        open("duration", in: app); choose(0, in: app)
        let selected = try inspect(app)
        bytes(selected.draft.players, exactPlayers); XCTAssertEqual(selected.draft.duration, 45)
        reads(selected, [playersRead, playersRead, durationRead, durationRead])
        try saveAndRestore(app)
        let restored = try inspect(app)
        bytes(restored.draft.players, exactPlayers); XCTAssertEqual(restored.draft.duration, 45)
        XCTAssertNil(restored.draft.activityCategoryids)
        tap("templateAuthor.reviewDraft", in: app); tap("templateAuthor.cancelReview", in: app)
        gone(app.buttons["templateAuthor.cancelReview"], in: app)
        XCTAssertEqual(try inspect(app).state, "editing")
        let locked = try confirmDraft(app)
        let request = try XCTUnwrap(locked.lastRequestFields)
        bytes(request.players, exactPlayers); XCTAssertEqual(request.duration, 45)
        XCTAssertNil(request.activityCategoryids); XCTAssertEqual(request.categoryId, 4)
        bytes(locked.draft.players, exactPlayers); XCTAssertEqual(locked.draft.duration, 45)
        reads(locked, [playersRead, playersRead, durationRead, durationRead])
    }

    // UNMEASURED estimate: 360 seconds. Five category reads, zero synthetic writes, 16 IDs without a cap.
    func testCategorySaveCancelNoopCSVAndOrderedSixteenSelections() throws {
        let app = launch("categories")
        bytes(try inspect(app).draft.activityCategoryids, originalCSV)
        open("categories", in: app); saved(originalCSV, in: app)
        _ = category(999, in: app, selected: true)
        _ = category(11, in: app, selected: true)
        _ = category(12, in: app, selected: true)
        close(app, save: true)
        bytes(try inspect(app).draft.activityCategoryids, originalCSV)
        open("categories", in: app); toggle(101, in: app); close(app)
        bytes(try inspect(app).draft.activityCategoryids, originalCSV)
        open("categories", in: app); toggle(101, in: app); toggle(101, in: app, from: true)
        close(app, save: true)
        bytes(try inspect(app).draft.activityCategoryids, originalCSV)
        open("categories", in: app)
        toggle(103, in: app); toggle(101, in: app, towardTop: true); toggle(102, in: app)
        for id in 104...113 { toggle(id, in: app) }
        close(app, save: true)
        let changed = try inspect(app)
        bytes(changed.draft.activityCategoryids, selectedCSV); XCTAssertEqual(changed.draft.categoryId, 777)
        XCTAssertEqual(selectedCSV.split(separator: ",").count, 16)
        reads(changed, Array(repeating: categoriesRead, count: 4))
        try saveAndRestore(app)
        let restored = try inspect(app)
        bytes(restored.draft.activityCategoryids, selectedCSV); XCTAssertEqual(restored.draft.categoryId, 777)
        open("categories", in: app); saved(selectedCSV, in: app)
        _ = category(999, in: app, selected: true)
        for id in [11, 12] + Array(101...113) { _ = category(id, in: app, selected: true) }
        close(app)
        let final = try inspect(app)
        bytes(final.draft.activityCategoryids, selectedCSV); XCTAssertEqual(final.draft.categoryId, 777)
        reads(final, Array(repeating: categoriesRead, count: 5))
    }

    // UNMEASURED estimate: 420 seconds. Actual canceled continuation and owner switch precede a fresh owner's confirmation.
    func testUnavailableRetryEmptyCanceledReadOwnerSwitchAndLockedValues() throws {
        let app = launch("lifecycle")
        open("players", in: app); saved("retired:group", in: app)
        XCTAssertTrue(app.staticTexts["templateMetadata.unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["templateMetadata.option.0"].exists); close(app)
        open("players", in: app)
        XCTAssertTrue(app.buttons["templateMetadata.retry"].waitForExistence(timeout: 5))
        saved("retired:group", in: app); tap("templateMetadata.retry", in: app)
        XCTAssertTrue(app.staticTexts["templateMetadata.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["templateMetadata.option.0"].exists); close(app)
        open("duration", in: app); saved("17", in: app)
        _ = option(4, in: app, enabled: false); close(app)
        open("categories", in: app); saved("999", in: app)
        XCTAssertTrue(category(999, in: app, selected: true).label.contains("999")); close(app)
        let historical = try inspect(app)
        bytes(historical.draft.players, "retired:group"); XCTAssertEqual(historical.draft.duration, 17)
        bytes(historical.draft.activityCategoryids, "999"); XCTAssertEqual(historical.draft.categoryId, 777)
        let beforeHold = [playersRead, playersRead, playersRead, durationRead, categoriesRead]
        reads(historical, beforeHold)
        open("players", in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Loading choices…")).firstMatch.waitForExistence(timeout: 5))
        close(app)
        let held = try inspect(app)
        reads(held, beforeHold + [playersRead], pending: 1)
        bytes(held.draft.players, "retired:group")
        // This ordinary host control invalidates the old owner BEFORE completing the held read.
        tap("templateAuthor.fixture.switch", in: app)
        XCTAssertTrue(app.buttons["templateAuthor.begin"].waitForExistence(timeout: 5))
        gone(app.buttons["templateMetadata.cancel"], in: app)
        let switched = try inspect(app)
        XCTAssertEqual(switched.accountID, 902); XCTAssertEqual(switched.draft.title, "")
        XCTAssertNil(switched.draft.players); XCTAssertNil(switched.draft.duration)
        XCTAssertNil(switched.draft.activityCategoryids); XCTAssertNil(switched.draft.categoryId)
        reads(switched, beforeHold + [playersRead])
        XCTAssertFalse(app.staticTexts["Late old owner"].exists)
        tap("templateAuthor.begin", in: app)
        let title = app.textFields["templateAuthor.field.title"]
        reveal(title, in: app); title.tap(); title.typeText("New owner metadata")
        tap("templateAuthor.continue", in: app)
        open("players", in: app); choose(0, in: app)
        open("duration", in: app); choose(0, in: app)
        open("categories", in: app); toggle(12, in: app); close(app, save: true)
        let selected = try inspect(app)
        bytes(selected.draft.players, exactPlayers); XCTAssertEqual(selected.draft.duration, 45)
        bytes(selected.draft.activityCategoryids, "12"); XCTAssertNil(selected.draft.categoryId)
        let allReads = beforeHold + [playersRead, playersRead, durationRead, categoriesRead]
        reads(selected, allReads)
        let locked = try confirmDraft(app)
        XCTAssertEqual(locked.accountID, 902); XCTAssertEqual(locked.draft.title, "New owner metadata")
        bytes(locked.draft.players, exactPlayers); XCTAssertEqual(locked.draft.duration, 45)
        bytes(locked.draft.activityCategoryids, "12"); XCTAssertNil(locked.draft.categoryId)
        let request = try XCTUnwrap(locked.lastRequestFields)
        XCTAssertEqual(request.title, "New owner metadata"); bytes(request.players, exactPlayers)
        XCTAssertEqual(request.duration, 45); bytes(request.activityCategoryids, "12"); XCTAssertNil(request.categoryId)
        lockedValue("players", exactPlayers, in: app, towardTop: true)
        lockedValue("duration", "45", in: app); lockedValue("categories", "12", in: app)
        reads(try inspect(app, requests: 1, locked: true), allReads)
        tap("templateAuthor.fixture.signOut", in: app)
        XCTAssertTrue(app.staticTexts["templateAuthor.signIn"].waitForExistence(timeout: 5))
        for field in ["players", "duration", "categories"] { XCTAssertFalse(app.buttons["templateMetadata.open." + field].exists) }
        let signedOut = try inspect(app, requests: 1)
        XCTAssertNil(signedOut.accountID); XCTAssertEqual(signedOut.draft.title, "")
        XCTAssertNil(signedOut.draft.players); XCTAssertNil(signedOut.draft.duration); XCTAssertNil(signedOut.draft.activityCategoryids)
        reads(signedOut, allReads)
    }
}
