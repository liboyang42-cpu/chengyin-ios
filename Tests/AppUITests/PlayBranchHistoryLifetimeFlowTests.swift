import XCTest

/// Full normal-summary journeys against the DEBUG offline read-only transport.
/// Runtime results and screenshots require an Apple simulator; source presence is not a pass.
final class PlayBranchHistoryLifetimeFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func launch(_ scenario: String = "recorded", chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playBranchHistory", "--branch-history-scenario", scenario,
            "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-reduce-motion"]
        if chinese { app.launchArguments += ["--uitesting-max-text", "--uitesting-dark"] }
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func open(_ app: XCUIApplication) {
        let button = app.buttons["branchHistory.open"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertTrue(revealFixtureElement(button, in: app)); button.tap()
        XCTAssertTrue(app.buttons["branchHistory.close"].waitForExistence(timeout: 5))
    }



    func testRefreshAndAccountSwitchWhilePresentedRemoveOldSheetAndRows() {
        for action in ["branchHistory.fixture.delayedRefresh", "branchHistory.fixture.delayedSwitch"] {
            let app = launch()
            XCTAssertTrue(app.buttons["branchHistory.open"].waitForExistence(timeout: 5))
            app.buttons["branchHistory.fixture.menu"].tap(); app.buttons[action].tap(); open(app)
            let oldRow = element("branchHistory.row.0", in: app)
            XCTAssertTrue(oldRow.waitForExistence(timeout: 5)); XCTAssertTrue(revealFixtureElement(oldRow, in: app))
            XCTAssertTrue(oldRow.isHittable); XCTAssertTrue(oldRow.label.contains("Synthetic courtyard"))
            let apply = app.buttons["branchHistory.fixture.applyPresented"]
            XCTAssertTrue(apply.waitForExistence(timeout: 5)); XCTAssertTrue(apply.isHittable); apply.tap()
            let close = app.buttons["branchHistory.close"]
            let gone = NSPredicate(format: "exists == false")
            expectation(for: gone, evaluatedWith: close); waitForExpectations(timeout: 8)
            XCTAssertFalse(element("branchHistory.row.0", in: app).exists)
            open(app); XCTAssertTrue(element("branchHistory.empty", in: app).waitForExistence(timeout: 5))
            app.buttons["branchHistory.close"].tap(); app.terminate()
        }
    }
    func testLinearSummaryHasNoHistoryEntryBeforeOrAfterRefresh() {
        let app = launch("linear")
        XCTAssertTrue(app.buttons["playx.refresh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["branchHistory.open"].exists)
        app.buttons["playx.refresh"].tap()
        XCTAssertTrue(app.staticTexts["referenceTask.count"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["branchHistory.open"].exists)
    }
}
