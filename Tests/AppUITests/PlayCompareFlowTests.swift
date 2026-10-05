import XCTest

final class PlayCompareFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(inline: Bool = false, unknown: Bool = false, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "compareGame", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if inline { app.launchArguments.append("--compare-inline") }
        if unknown { app.launchArguments.append("--compare-unknown") }
        runningApp = app; app.launch()
        if !inline {
            let open = app.buttons["playkit.open.compare"]
            XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription); open.tap()
        }
        XCTAssertTrue(app.buttons["playkit.compare.item.left_gate"].waitForExistence(timeout: 5), app.debugDescription)
        return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        if id == "playkit.close" {
            let close = app.navigationBars.buttons[id]
            XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(close.isEnabled && close.isHittable, app.debugDescription)
            close.tap(); return
        }
        let element = app.buttons[id]
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription); element.tap()
    }
    private func confirm(_ app: XCUIApplication) {
        tap("playkit.submit.compare", app)
        let confirm = app.buttons["playkit.review.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(confirm, in: app), app.debugDescription); confirm.tap()
    }
    func testNativeTimelineQuestionAndReadableReviewCanCancelWithoutSubmission() {
        let app = launch()
        tap("playkit.compare.item.left_gate", app); tap("playkit.compare.item.right_gate", app)
        tap("playkit.submit.compare", app)
        XCTAssertTrue(app.staticTexts["The gate opened."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The gate stayed closed."].exists)
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["compare.fixture.writes"].label, "0")
        XCTAssertTrue(app.buttons["playkit.submit.compare"].exists)
    }
    func testExactBothSideSelectionShowsServerReceiptAndClosesInputs() {
        let app = launch()
        tap("playkit.compare.item.left_gate", app); tap("playkit.compare.item.right_gate", app); confirm(app)
        XCTAssertTrue(app.staticTexts["playkit.compare.receipt"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["playkit.compare.receipt"].label, "The server marked the complete selection correct.")
        XCTAssertFalse(app.buttons["playkit.submit.compare"].exists)
        XCTAssertEqual(app.staticTexts["compare.fixture.writes"].label, "1")
    }
    func testEmptySelectionIsReviewableAndCountsAsFailedAttempt() {
        let app = launch(inline: true)
        tap("playkit.submit.compare", app)
        XCTAssertTrue(app.staticTexts["No entries marked. Submitting still counts as an attempt."].waitForExistence(timeout: 3))
        tap("playkit.review.confirm", app)
        XCTAssertTrue(app.staticTexts["playkit.compare.receipt"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["compare.fixture.writes"].label, "1")
        XCTAssertFalse(app.buttons["playkit.submit.compare"].isEnabled)
        tap("playkit.compare.reload", app)
        let reloadSheet = app.sheets.firstMatch
        XCTAssertTrue(reloadSheet.waitForExistence(timeout: 3), app.debugDescription)
        tapFixtureSheetAction("Replace selection with latest receipt", in: reloadSheet, app: app)
        confirm(app)
        XCTAssertEqual(app.staticTexts["compare.fixture.writes"].label, "2")
        XCTAssertFalse(app.buttons["playkit.submit.compare"].exists)
    }
    func testUnknownResultReconcilesAndReplaysWithoutDoubleAttempt() {
        let app = launch(inline: true, unknown: true)
        tap("playkit.compare.item.left_gate", app); tap("playkit.compare.item.right_gate", app); confirm(app)
        // Source-localized recovery controls remain the same outlet as every kit.
        let read = app.buttons["playkit.compare.reconcile"]
        XCTAssertTrue(read.waitForExistence(timeout: 3))
        XCTAssertTrue(revealFixtureElement(read, in: app), app.debugDescription); read.tap()
        let retry = app.buttons["playkit.compare.retryExact"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3)); retry.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: retry)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(app.staticTexts["compare.fixture.writes"].label, "1")
    }
    func testRefreshNeverSilentlyRebasesUnsentSelection() {
        let app = launch(inline: true)
        tap("playkit.compare.item.left_gate", app); tap("playkit.compare.refresh", app)
        let reload = app.buttons["playkit.compare.reload"]
        XCTAssertTrue(reload.waitForExistence(timeout: 3)); XCTAssertFalse(app.buttons["playkit.submit.compare"].isEnabled)
        XCTAssertEqual(app.staticTexts["compare.fixture.writes"].label, "0")
    }
    func testChineseNativeComparisonAndCloseDiscardFlow() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.navigationBars["时间轴对照"].exists)
        tap("playkit.compare.item.left_gate", app); tap("playkit.close", app)
        let keep = app.buttons["继续编辑"]
        if keep.exists && keep.isHittable { keep.tap() }
        else { dismissFixtureConfirmationPopover(in: app) }
        XCTAssertTrue(app.buttons["playkit.submit.compare"].exists)
        XCTAssertEqual(app.buttons["playkit.compare.item.left_gate"].value as? String, "已标记")
        XCTAssertEqual(app.staticTexts["compare.fixture.writes"].label, "0")
    }
}
