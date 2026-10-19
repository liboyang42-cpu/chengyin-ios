import XCTest

/// Synthetic offline 时光胶囊 / 探索目标 / 导出探索记录. No account, network, location or file system writes are asserted.
final class RoamPassportPrivateToolsFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String = "content") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", scenario,
            "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func open(_ id: String, _ app: XCUIApplication) {
        XCTAssertTrue(element("roam.experience.hub", app).waitForExistence(timeout: 8))
        let target = app.buttons[id]; XCTAssertTrue(revealFixtureElement(target, in: app)); target.tap()
    }
    private func tap(_ id: String, _ app: XCUIApplication, towardTop: Bool = false) {
        let target = app.buttons[id]
        XCTAssertTrue(target.waitForExistence(timeout: 5), id)
        XCTAssertTrue(revealFixtureElement(target, in: app, towardTop: towardTop), id)
        target.tap()
    }

    func testCapsuleListsLockedAndOpenAndSealsOnlyAfterConfirmation() {
        let app = app()
        open("roam.capsule.open", app)
        XCTAssertTrue(element("roam.capsule.row.locked", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("roam.capsule.row.open", app).exists)
        XCTAssertTrue(element("roam.capsule.row.locked", app).label.contains("46 days"), element("roam.capsule.row.locked", app).label)
        tap("roam.capsule.row.open", app)
        XCTAssertTrue(element("roam.capsule.body", app).waitForExistence(timeout: 5))
        tap("roam.capsule.keep", app)
        XCTAssertTrue(element("roam.capsule.row.open", app).waitForExistence(timeout: 5))
        tap("roam.capsule.write", app, towardTop: true)
        let text = app.textViews["roam.capsule.text"].exists ? app.textViews["roam.capsule.text"] : app.textFields["roam.capsule.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("Synthetic note")
        tap("roam.capsule.unlock.30", app)
        tap("roam.capsule.seal", app)
        let confirm = app.sheets.buttons["Seal capsule"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Sealing needs an explicit confirmation")
        confirm.tap()
        let locked = app.descendants(matching: .any).matching(identifier: "roam.capsule.row.locked")
        XCTAssertTrue(locked.element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertEqual(locked.count, 2)
        XCTAssertFalse(element("roam.capsule.pending", app).exists)
    }

    func testUnconfirmedSealStaysPendingUntilReceiptCheck() {
        let app = app("privateUnknown")
        open("roam.capsule.open", app)
        XCTAssertTrue(element("roam.capsule.row.locked", app).waitForExistence(timeout: 5))
        tap("roam.capsule.write", app, towardTop: true)
        let text = app.textViews["roam.capsule.text"].exists ? app.textViews["roam.capsule.text"] : app.textFields["roam.capsule.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5)); text.tap(); text.typeText("Synthetic note")
        tap("roam.capsule.seal", app)
        let confirm = app.sheets.buttons["Seal capsule"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(element("roam.capsule.pending", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["roam.capsule.retryOriginal"].exists)
        tap("roam.capsule.verify", app, towardTop: true)
        XCTAssertTrue(element("roam.capsule.pending", app).waitForAbsence(timeout: 5))
    }

    func testGoalsCreateAndCancelWithExplicitConfirmation() {
        let app = app()
        open("roam.goals.open", app)
        let rows = app.descendants(matching: .any).matching(identifier: "roam.goals.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2)
        tap("roam.goals.new", app, towardTop: true)
        tap("roam.goals.create", app)
        let confirm = app.sheets.buttons["Create goal"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Creating needs an explicit confirmation")
        confirm.tap()
        XCTAssertTrue(element("roam.goals.detail.progress", app).waitForExistence(timeout: 5))
        XCTAssertTrue(rows.element(boundBy: 2).waitForExistence(timeout: 5))
        tap("roam.goals.cancelThis", app)
        let cancel = app.sheets.buttons["Cancel goal"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons["roam.goals.cancelThis"].waitForAbsence(timeout: 5), "A cancelled goal cannot be cancelled again")
    }

    func testExportReadsEveryChunkBeforeOfferingTheFile() {
        let app = app()
        open("roam.export.open", app)
        tap("roam.export.prepare", app)
        XCTAssertTrue(element("roam.export.progress", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roam.export.share"].exists)
        tap("roam.export.readNext", app)
        XCTAssertTrue(element("roam.export.progress", app).label.contains("2 / 3") || app.staticTexts["Read 2 / 3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roam.export.share"].exists, "A partial export is never offered")
        tap("roam.export.readNext", app)
        XCTAssertTrue(element("roam.export.file", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["roam.export.share"].exists)
        XCTAssertTrue(app.buttons["roam.export.save"].exists)
        tap("roam.export.restart", app)
        XCTAssertTrue(app.buttons["roam.export.prepare"].waitForExistence(timeout: 5))
    }

    func testReadOnlyApprovalShowsRecordsButNoWriteActions() {
        let app = app("privateReadOnly")
        open("roam.goals.open", app)
        XCTAssertTrue(element("roam.goals.row", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("roam.goals.writesDisabled", app).exists)
        tap("roam.goals.row", app)
        XCTAssertTrue(element("roam.goals.detail.progress", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roam.goals.cancelThis"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("roam.capsule.open", app)
        XCTAssertTrue(element("roam.capsule.writesDisabled", app).waitForExistence(timeout: 5))
        tap("roam.capsule.write", app, towardTop: true)
        XCTAssertFalse(app.buttons["roam.capsule.seal"].isEnabled)
    }

    func testEmptyPrivateToolsShowHonestEmptyStates() {
        let app = app("empty")
        open("roam.capsule.open", app)
        XCTAssertTrue(element("roam.capsule.empty", app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("roam.goals.open", app)
        XCTAssertTrue(element("roam.goals.empty", app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("roam.export.open", app)
        tap("roam.export.prepare", app)
        tap("roam.export.readNext", app)
        XCTAssertTrue(element("roam.export.noRecords", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roam.export.share"].exists, "Zero rows: no empty file to share")
    }
}

private extension XCUIElement {
    func waitForAbsence(timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
