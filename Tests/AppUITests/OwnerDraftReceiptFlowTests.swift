import XCTest

final class OwnerDraftReceiptFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ mode: String = "ready", language: String = "en", maximum: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--owner-draft-fixture", mode, "--uitesting-reset-language", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if maximum { app.launchArguments.append("--uitesting-max-text") }
        app.launch()
        record("session", mode == "guest" ? "guest" : "signed-in", app)
        if mode != "guest" { record("authPaths", "phone,userInfo", app) }
        return app
    }
    // These controls live outside the scrolling content viewport. Keep the row
    // reveal helper strict; never scroll a fixed navigation/footer action into it.
    private func fixedControlIsReady(_ id: String, _ app: XCUIApplication) -> Bool {
        let element: XCUIElement
        switch id {
        case "ownerDraft.refresh": element = app.navigationBars.buttons[id]
        case "ownerDraft.fixture.release", "ownerDraft.fixture.replace": element = app.buttons[id]
        default: return false
        }
        guard element.exists, element.isEnabled, element.isHittable,
              !element.frame.isEmpty, app.frame.contains(element.frame) else { return false }
        return !app.keyboards.allElementsBoundByIndex.contains { $0.frame.intersects(element.frame) }
    }
    private func tap(_ id: String, _ app: XCUIApplication, diagnoseEntry: Bool = false) {
        let element = app.buttons[id]
        if ["ownerDraft.refresh", "ownerDraft.fixture.release", "ownerDraft.fixture.replace"].contains(id) {
            XCTAssertTrue(fixedControlIsReady(id, app), app.debugDescription)
        } else {
            XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription)
        }
        if diagnoseEntry { captureEntryBoundary(app, stage: "before single tap") }
        element.tap()
        if diagnoseEntry { captureEntryBoundary(app, stage: "after single tap") }
    }
    private func captureEntryBoundary(_ app: XCUIApplication, stage: String) {
        // Only this synthetic owner-draft fixture opts in. Print selected AX and
        // payload-free counters because CI screenshot exports omit AX attachments.
        guard app.launchArguments.contains("--owner-draft-fixture") else { return }
        // Take one app snapshot. Checking target.exists and then asking for its
        // properties races the navigation that intentionally removes that target.
        // Diagnostics must never turn a successful transition into a failed lookup.
        let snapshot = String(app.debugDescription.prefix(65_536))
        let lines = snapshot.split(separator: "\n").map(String.init)
        func matching(_ identifier: String) -> [String] {
            lines.filter { $0.contains("identifier: '\(identifier)'") }
        }
        let entry = matching("account.ownerDrafts")
        print("OWNER_DRAFT_ENTRY stage=\(stage); snapshotOnly=true; identifier=account.ownerDrafts; matches=\(entry.count)")
        for line in entry.prefix(4) { print("OWNER_DRAFT_ENTRY_TARGET_AX " + String(line.prefix(1024))) }
        for line in lines.filter({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("NavigationBar,") }).prefix(4) {
            print("OWNER_DRAFT_ENTRY_NAVIGATION_AX " + String(line.prefix(1024)))
        }
        for name in ["session", "authPaths", "list", "restore", "mutations", "pending"] {
            let rows = matching("ownerDraft.recorder.\(name)")
            print("OWNER_DRAFT_ENTRY_RECORDER \(name)=\(rows.isEmpty ? "absent" : String(rows.joined(separator: " | ").prefix(1024)))")
        }
        for id in ["ownerDraft.loading", "ownerDraft.empty", "ownerDraft.error", "ownerDraft.notConfigured", "ownerDraft.row.11"] {
            print("OWNER_DRAFT_ENTRY_DESTINATION \(id)=\(matching(id).count)")
        }
        attachFixtureScreenshot(self, app: app, name: "Owner draft account entry " + stage)
    }
    private func record(_ name: String, _ value: String, _ app: XCUIApplication) {
        let element = app.staticTexts["ownerDraft.recorder.\(name)"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let expected = expectation(for: NSPredicate(format: "label == %@", value), evaluatedWith: element)
        wait(for: [expected], timeout: 5); XCTAssertEqual(element.label, value)
    }
    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }












    func testHistoricalReceiptShowsStaleBindingAndNoContentActions() {
        let app = launch("receipts-stale"); tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["Draft revision has changed. This receipt has not been reattached."], in: app))
        XCTAssertTrue(revealFixtureElement(app.staticTexts["2026-10-03T00:00:00.123456Z"], in: app))
        record("restore", "1", app); record("mutations", "0", app)
        XCTAssertEqual(app.textViews.count, 0); XCTAssertEqual(app.textFields.count, 0)
        XCTAssertFalse(app.staticTexts["synthetic-module-version"].exists)
    }
    func testOldServerOmissionDoesNotClaimEmptyInstallationHistory() {
        let app = launch(); tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["This server did not provide installed-module receipt information."], in: app))
        XCTAssertFalse(app.staticTexts["ownerDraft.receipts.empty"].exists); record("mutations", "0", app)
    }
    func testExplicitEmptyHistoryIsVisible() {
        let app = launch("receipts-empty"); tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["ownerDraft.receipts.empty"], in: app))
        record("mutations", "0", app)
    }
    func testInvalidCapabilityCannotRenderHistoricalReceipt() {
        let app = launch("receipts-invalid"); tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["Receipt information could not be verified for this draft revision."], in: app))
        XCTAssertFalse(app.staticTexts["2026-10-03T00:00:00.123456Z"].exists)
        record("mutations", "0", app)
    }
    func testReceiptBackReopenAndLifetimeReplacementClearHistoricalMetadata() {
        let app = launch("receipts-unverifiable"); tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["Original draft binding cannot be verified."], in: app))
        back(app); tap("ownerDraft.row.12", app)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["Original draft binding cannot be verified."], in: app))
        record("restore", "2", app); tap("ownerDraft.fixture.replace", app)
        XCTAssertTrue(app.staticTexts["ownerDraft.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Original draft binding cannot be verified."].exists)
        record("mutations", "0", app)
    }
    func testChineseMaximumTypeReceiptPolicyAndUnverifiableBinding() {
        let app = launch("receipts-unverifiable", language: "zh-Hans", maximum: true)
        tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["无法核验原始草稿绑定。"], in: app))
        record("mutations", "0", app); XCTAssertEqual(app.textViews.count, 0)
    }


}
