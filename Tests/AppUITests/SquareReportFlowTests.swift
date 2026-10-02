import XCTest

/// Normal v1 Square feed -> detail -> report, using explicitly synthetic local adapters.
/// These cases are authored here; Apple runtime/screenshot results remain a separate gate.
final class SquareReportFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func reveal(_ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<10 { if element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func tap(_ id: String) { let element = app.buttons[id]; reveal(element); element.tap() }
    private func launch(_ scenario: String = "content", language: String = "en", extra: [String] = []) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-module", "socialAccount", "--uitesting-social-destination", "reports", "--uitesting-social-scenario", scenario] + extra
        app.launch(); tap("square.row.701")
    }
    private func openReport() { tap("social.post.actions"); tap("squareReport.postEntry") }
    private func chooseReason(_ code: String = "SPAM") {
        tap("squareReport.chooseReason"); tap("squareReport.reason." + code)
    }
    private func enterFacts() {
        let editor = app.textViews["squareReport.description"]; reveal(editor); editor.tap(); editor.typeText("Synthetic report facts")
        tap("squareReport.keyboardDone"); XCTAssertFalse(app.keyboards.firstMatch.exists)
    }
    func testNormalEntryRequiresReasonAndFactsAndReviewBackPreservesBoth() {
        launch(); openReport()
        let review = app.buttons["squareReport.review"]; reveal(review); XCTAssertFalse(review.isEnabled)
        chooseReason(); reveal(review); XCTAssertFalse(review.isEnabled)
        enterFacts(); tap("squareReport.review")
        XCTAssertTrue(app.buttons["squareReport.confirm"].waitForExistence(timeout: 5))
        attachFixtureScreenshot(self, app: app, name: "Versioned Square report immutable reason-policy review - synthetic")
        tap("squareReport.reviewBack")
        XCTAssertEqual(app.textViews["squareReport.description"].value as? String, "Synthetic report facts")
        XCTAssertTrue(app.buttons["squareReport.chooseReason"].label.contains("Spam"))
        tap("squareReport.close"); tap("squareReport.keepEditing")
        XCTAssertEqual(app.textViews["squareReport.description"].value as? String, "Synthetic report facts")
    }
    func testSyntheticAcknowledgementReadsBackExactCaseWithoutResubmission() {
        launch(); openReport(); chooseReason(); enterFacts(); tap("squareReport.review"); tap("squareReport.confirm")
        XCTAssertTrue(app.staticTexts["squareReport.acknowledged"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["squareReport.acknowledged"].label.contains("No real report"))
        tap("squareReport.refresh")
        let status = app.descendants(matching: .any)["squareReport.stage"].firstMatch
        reveal(status)
        XCTAssertTrue(app.staticTexts["IN_REVIEW"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["squareReport.review"].exists)
        attachFixtureScreenshot(self, app: app, name: "Versioned Square report case readback - synthetic IN_REVIEW")
    }
    func testChangedPolicyClearsReasonAndDoesNotAcknowledgeSubmission() {
        launch("reportPolicyChanged"); openReport(); chooseReason(); enterFacts(); tap("squareReport.review"); tap("squareReport.confirm")
        XCTAssertTrue(app.staticTexts["squareReport.message"].waitForExistence(timeout: 5))
        reveal(app.buttons["squareReport.review"]); XCTAssertFalse(app.buttons["squareReport.review"].isEnabled)
        XCTAssertFalse(app.staticTexts["squareReport.acknowledged"].exists)
        XCTAssertEqual(app.textViews["squareReport.description"].value as? String, "Synthetic report facts")
        attachFixtureScreenshot(self, app: app, name: "Changed report policy requires fresh reason selection - synthetic")
    }
    func testUnknownOutcomeRemainsLockedAfterCloseAndReopen() {
        launch("reportUnknown"); openReport(); chooseReason(); enterFacts(); tap("squareReport.review"); tap("squareReport.confirm")
        XCTAssertTrue(app.staticTexts["squareReport.locked"].waitForExistence(timeout: 5))
        tap("squareReport.close"); openReport()
        XCTAssertTrue(app.staticTexts["squareReport.locked"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["squareReport.review"].exists)
        XCTAssertFalse(app.staticTexts["squareReport.acknowledged"].exists)
        attachFixtureScreenshot(self, app: app, name: "Unconfirmed report stays locked after reopening - synthetic")
    }
    func testChangedContentRefreshesQualifiedTargetAndRequiresAnotherReview() {
        launch("reportContentChanged"); openReport(); chooseReason(); enterFacts(); tap("squareReport.review"); tap("squareReport.confirm")
        let subject = app.staticTexts["squareReport.subject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 5)); XCTAssertEqual(subject.label, "Synthetic revised community post")
        let review = app.buttons["squareReport.review"]; reveal(review); XCTAssertFalse(review.isEnabled)
        XCTAssertFalse(app.staticTexts["squareReport.acknowledged"].exists)
        XCTAssertEqual(app.textViews["squareReport.description"].value as? String, "Synthetic report facts")
        attachFixtureScreenshot(self, app: app, name: "Changed Square content refreshed with saved draft and cleared reason - synthetic")
        chooseReason(); tap("squareReport.review"); tap("squareReport.confirm")
        XCTAssertTrue(app.staticTexts["squareReport.acknowledged"].waitForExistence(timeout: 5))
    }
    func testChineseLargeTextReasonSheetCancelsWithoutSelecting() {
        launch(language: "zh-Hans", extra: ["--uitesting-large-text", "--uitesting-dark-mode"])
        openReport(); tap("squareReport.chooseReason")
        let first = app.buttons["squareReport.reason.DANGEROUS"]; reveal(first)
        attachFixtureScreenshot(self, app: app, name: "Chinese report reason nested sheet large text dark mode - synthetic")
        tap("squareReport.reasonCancel")
        let review = app.buttons["squareReport.review"]; reveal(review); XCTAssertFalse(review.isEnabled)
        chooseReason("OTHER"); enterFacts(); tap("squareReport.review")
        attachFixtureScreenshot(self, app: app, name: "Chinese report review large text dark mode - synthetic")
    }
}
