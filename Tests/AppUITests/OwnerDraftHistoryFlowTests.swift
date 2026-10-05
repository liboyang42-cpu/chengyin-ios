import XCTest

final class OwnerDraftHistoryFlowTests: XCTestCase {
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
    func testCappedHistoryDisclosesMoreWithoutInventingPagination() {
        let app = launch("receipts-capped"); tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["ownerDraft.receipts.hasMore"], in: app))
        record("restore", "1", app); record("mutations", "0", app)
        XCTAssertFalse(app.buttons["Load more"].exists)
    }
}
