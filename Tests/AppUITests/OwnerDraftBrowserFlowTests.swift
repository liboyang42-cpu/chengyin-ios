import XCTest

final class OwnerDraftBrowserFlowTests: XCTestCase {
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
        let target = app.buttons["account.ownerDrafts"]
        let exists = target.exists
        print("OWNER_DRAFT_ENTRY stage=\(stage); identifier=account.ownerDrafts; type=\(exists ? String(target.elementType.rawValue) : "absent"); exists=\(exists); enabled=\(exists && target.isEnabled); hittable=\(exists && target.isHittable); frame=\(exists ? target.frame : .zero)")
        if exists { print("OWNER_DRAFT_ENTRY_TARGET_AX " + String(target.debugDescription.prefix(8192))) }
        print("OWNER_DRAFT_ENTRY_NAVIGATION_AX " + String(app.navigationBars.debugDescription.prefix(8192)))
        for name in ["session", "authPaths", "list", "restore", "mutations", "pending"] {
            let counter = app.staticTexts["ownerDraft.recorder.\(name)"]
            print("OWNER_DRAFT_ENTRY_RECORDER \(name)=\(counter.exists ? counter.label : "absent")")
        }
        for id in ["ownerDraft.loading", "ownerDraft.empty", "ownerDraft.error", "ownerDraft.notConfigured", "ownerDraft.row.11"] {
            print("OWNER_DRAFT_ENTRY_DESTINATION \(id)=\(app.descendants(matching: .any).matching(identifier: id).count)")
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
    func testActualAccountEntryListsActivityTopicAndShowsUnsupportedEditor() {
        let app = launch(); tap("account.ownerDrafts", app, diagnoseEntry: true)
        let arrived = app.buttons["ownerDraft.row.11"].waitForExistence(timeout: 5)
        captureEntryBoundary(app, stage: "after original row wait")
        XCTAssertTrue(arrived)
        XCTAssertTrue(revealFixtureElement(app.buttons["ownerDraft.row.12"], in: app))
        tap("ownerDraft.row.11", app)
        XCTAssertTrue(app.staticTexts["Payload editing unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2026-10-03T08:00:00+08:00"].exists)
        record("list", "1", app); record("restore", "1", app); record("mutations", "0", app)
        XCTAssertEqual(app.textViews.count, 0); XCTAssertEqual(app.textFields.count, 0)
    }
    func testEmptyAndRefreshStayReadOnly() {
        let app = launch("empty"); tap("account.ownerDrafts", app)
        XCTAssertTrue(app.staticTexts["ownerDraft.empty"].waitForExistence(timeout: 5))
        tap("ownerDraft.refresh", app); record("list", "2", app); record("mutations", "0", app)
    }
    func testErrorRetryUsesSameRealEntry() {
        let app = launch("error"); tap("account.ownerDrafts", app)
        XCTAssertTrue(app.staticTexts["ownerDraft.error"].waitForExistence(timeout: 5))
        tap("ownerDraft.retry", app); XCTAssertTrue(app.buttons["ownerDraft.row.11"].waitForExistence(timeout: 5))
        record("list", "2", app); record("mutations", "0", app)
    }
    func testLoadingReleaseAndRestoreRetry() {
        let app = launch("loading"); tap("account.ownerDrafts", app)
        XCTAssertTrue(app.activityIndicators["ownerDraft.loading"].waitForExistence(timeout: 5))
        tap("ownerDraft.fixture.release", app); XCTAssertTrue(app.buttons["ownerDraft.row.11"].waitForExistence(timeout: 5))
        record("list", "1", app); record("mutations", "0", app)
    }
    func testFixedControlsRejectDisabledAndNonChromeTargets() {
        let app = launch("loading"); tap("account.ownerDrafts", app)
        XCTAssertTrue(app.activityIndicators["ownerDraft.loading"].waitForExistence(timeout: 5))
        XCTAssertFalse(fixedControlIsReady("ownerDraft.refresh", app))
        XCTAssertFalse(fixedControlIsReady("ownerDraft.row.11", app))
        XCTAssertTrue(fixedControlIsReady("ownerDraft.fixture.release", app))
        XCTAssertTrue(fixedControlIsReady("ownerDraft.fixture.replace", app))
        tap("ownerDraft.fixture.release", app)
        XCTAssertTrue(app.buttons["ownerDraft.row.11"].waitForExistence(timeout: 5))
        XCTAssertTrue(fixedControlIsReady("ownerDraft.refresh", app))
        record("list", "1", app); record("mutations", "0", app)
    }
    func testRestoreErrorCanRetryWithoutOpeningEditor() {
        let app = launch("restore-error"); tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        tap("ownerDraft.detailRetry", app)
        XCTAssertTrue(app.staticTexts["Payload editing unavailable"].waitForExistence(timeout: 5))
        record("restore", "2", app); record("mutations", "0", app)
    }
    func testUnconfiguredNormalAccountEntryDoesNotSendDraftRequests() {
        let app = launch("disabled"); tap("account.ownerDrafts", app)
        XCTAssertTrue(app.staticTexts["Cloud drafts unavailable"].waitForExistence(timeout: 5))
        record("list", "0", app); record("restore", "0", app); record("mutations", "0", app)
    }
    func testGuestEntryLoginSheetCanDismissWithoutGrantingAccess() {
        let app = launch("guest"); tap("ownerDraft.guestEntry", app); tap("ownerDraft.signIn", app)
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5)); app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["ownerDraft.signIn"].waitForExistence(timeout: 5)); record("list", "0", app)
    }
    func testListBackAndReopenReloadsThroughActualAccountEntry() {
        let app = launch(); tap("account.ownerDrafts", app)
        XCTAssertTrue(app.buttons["ownerDraft.row.11"].waitForExistence(timeout: 5))
        back(app); tap("account.ownerDrafts", app)
        XCTAssertTrue(app.buttons["ownerDraft.row.11"].waitForExistence(timeout: 5))
        record("list", "2", app); record("restore", "0", app); record("mutations", "0", app)
    }
    func testSuspendedListBackReopenDispatchesFreshReadBeforeOldCompletion() {
        let app = launch("loading"); tap("account.ownerDrafts", app)
        XCTAssertTrue(app.buttons["ownerDraft.fixture.release"].waitForExistence(timeout: 5))
        back(app); tap("account.ownerDrafts", app)
        let pending = app.staticTexts["ownerDraft.recorder.pending"]
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        let twoReads = expectation(for: NSPredicate(format: "label == '2'"), evaluatedWith: pending)
        wait(for: [twoReads], timeout: 5); record("list", "2", app)
        tap("ownerDraft.fixture.release", app)
        let retiredReleased = expectation(for: NSPredicate(format: "label == '1'"), evaluatedWith: pending)
        wait(for: [retiredReleased], timeout: 5)
        XCTAssertFalse(app.buttons["ownerDraft.row.11"].exists)
        tap("ownerDraft.fixture.release", app)
        XCTAssertTrue(app.buttons["ownerDraft.row.11"].waitForExistence(timeout: 5))
        record("pending", "0", app); record("mutations", "0", app)
    }
    func testBackReopenAndLifetimeReplacementClearOldMetadata() {
        let app = launch(); tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        XCTAssertTrue(app.staticTexts["Payload editing unavailable"].waitForExistence(timeout: 5))
        back(app); tap("ownerDraft.row.12", app)
        XCTAssertTrue(app.staticTexts["Payload editing unavailable"].waitForExistence(timeout: 5)); record("restore", "2", app)
        tap("ownerDraft.fixture.replace", app)
        XCTAssertTrue(app.staticTexts["ownerDraft.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Payload editing unavailable"].exists); record("mutations", "0", app)
    }
    func testChineseMaximumTypeRetainsMetadataAndUnsupportedNotice() {
        let app = launch(language: "zh-Hans", maximum: true); tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["暂不支持编辑草稿内容"], in: app))
        record("mutations", "0", app); XCTAssertEqual(app.textFields.count, 0)
    }
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

    func testCappedHistoryDisclosesMoreWithoutInventingPagination() {
        let app = launch("receipts-capped"); tap("account.ownerDrafts", app); tap("ownerDraft.row.11", app)
        XCTAssertTrue(revealFixtureElement(app.staticTexts["ownerDraft.receipts.hasMore"], in: app))
        record("restore", "1", app); record("mutations", "0", app)
        XCTAssertFalse(app.buttons["Load more"].exists)
    }

}
