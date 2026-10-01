import XCTest

/// Requires the DEBUG integration host: --uitesting-module square -> SquareFixtureHostView.
/// Fixture names and all data are synthetic; these tests never validate a deployed service.
final class SquareFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "square", "--uitesting-square-scenario", scenario]
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 4)
        for _ in 0..<10 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isEnabled, app.debugDescription, file: file, line: line)
        element.tap()
    }
    func testPostPaginationDetailCommentPaginationAndBack() {
        launch()
        XCTAssertTrue(app.navigationBars["Square"].waitForExistence(timeout: 10))
        reveal(app.buttons["square.loadMore"])
        reveal(app.buttons["square.row.703"])
        XCTAssertTrue(app.navigationBars["Post details"].waitForExistence(timeout: 5))
        reveal(app.buttons["square.moreComments"])
        let finalComment = app.descendants(matching: .any)["square.comment.803"].firstMatch
        for _ in 0..<4 { if finalComment.exists { break }; app.swipeUp() }
        XCTAssertTrue(finalComment.exists)
        XCTAssertFalse(app.buttons["Publish"].exists)
        app.navigationBars["Post details"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Square"].waitForExistence(timeout: 5))
    }
    func testPartialCommentFailurePreservesPostAndRetries() {
        launch("partial")
        XCTAssertTrue(app.descendants(matching: .any)["square.detailPost"].firstMatch.waitForExistence(timeout: 10))
        reveal(app.buttons["square.retry"])
        let comment = app.descendants(matching: .any)["square.comment.801"].firstMatch
        for _ in 0..<5 { if comment.exists { break }; app.swipeUp() }
        XCTAssertTrue(comment.exists)
    }
    func testPageFailureRetainsRowsAndRetriesSameCursor() {
        launch("pageFailure")
        reveal(app.buttons["square.loadMore"])
        for _ in 0..<10 { if app.buttons["square.retry"].exists && app.buttons["square.retry"].isHittable { break }; app.swipeDown() }
        reveal(app.buttons["square.retry"])
        reveal(app.buttons["square.row.703"])
        XCTAssertTrue(app.navigationBars["Post details"].waitForExistence(timeout: 5))
    }
    func testUnavailableDetailKeepsServerMessageAndNoComments() {
        launch("unavailable")
        XCTAssertTrue(app.staticTexts["Synthetic unavailable post / 示例内容不可用"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["square.detailPost"].firstMatch.exists)
        XCTAssertFalse(app.buttons["square.moreComments"].exists)
        reveal(app.buttons["square.retry"])
        XCTAssertTrue(app.staticTexts["Synthetic unavailable post / 示例内容不可用"].waitForExistence(timeout: 5))
    }
    func testChineseEmptyStateUsesLocalizedControls() {
        launch("empty", chinese: true)
        XCTAssertTrue(app.navigationBars["广场"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["暂无动态"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["square.empty"].exists)
    }
    func testSearchSubmitAndClearRestoreFeed() {
        launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("missing\n")
        XCTAssertTrue(app.staticTexts["No posts found"].waitForExistence(timeout: 5))
        field.tap()
        let clear = field.buttons.firstMatch
        XCTAssertTrue(clear.exists); clear.tap()
        XCTAssertTrue(app.buttons["square.row.701"].waitForExistence(timeout: 5))
    }
    func testDelayedOldFeedDoesNotReplaceNewSearch() {
        launch("delayed")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("missing\n")
        XCTAssertTrue(app.staticTexts["No posts found"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["square.row.701"].exists)
    }
    func testGuestFollowingShowsSignInGate() {
        launch()
        reveal(app.buttons["square.feed"])
        app.buttons["Following"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to view this feed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["square.row.701"].exists)
    }
    func testUnconfiguredAndUnauthorizedStayHonest() {
        launch("unconfigured")
        XCTAssertTrue(app.staticTexts["Square service is not configured"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["square.row.701"].exists)
        app.terminate(); launch("unauthorized")
        XCTAssertTrue(app.staticTexts["Your session could not be verified. Sign in again to continue"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["square.row.701"].exists)
    }
}
