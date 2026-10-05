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
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription, file: file, line: line)
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
        XCTAssertTrue(revealFixtureElement(app.buttons["square.retry"], in: app, towardTop: true), app.debugDescription)
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
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label == %@", "square.empty")).firstMatch.exists)
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
    // A one-row fixture List can rest exactly against the navigation bar and
    // cannot scroll to create the shared helper's extra four-point clearance.
    // Validate its entire actual native frame; do not accept a clipped row.
    private func tapRelatedFixturePost(file: StaticString = #filePath, line: UInt = #line) {
        let query = app.buttons.matching(identifier: "fixture.relatedPost")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard query.count == 1, self.app.navigationBars.count == 1 else { return false }
            let button = query.element(boundBy: 0), frame = button.frame
            let bar = self.app.navigationBars.element(boundBy: 0)
            return button.exists && button.isEnabled && button.isHittable && !frame.isEmpty &&
                self.app.frame.contains(frame) && frame.minY >= bar.frame.maxY &&
                frame.maxY <= self.app.frame.maxY - 40 &&
                !self.app.keyboards.allElementsBoundByIndex.contains { $0.frame.intersects(frame) }
        }, object: app)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            XCTFail("Expected one fully visible related-post fixture row: " + app.debugDescription, file: file, line: line); return
        }
        query.element(boundBy: 0).tap()
    }
    private func tapRelatedFixtureAccountSwitch(file: StaticString = #filePath, line: UInt = #line) {
        let query = app.navigationBars.buttons.matching(identifier: "fixture.relatedTopic.switchAccount")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard query.count == 1, self.app.navigationBars.count == 1 else { return false }
            let button = query.element(boundBy: 0), frame = button.frame
            return button.exists && button.isEnabled && button.isHittable && !frame.isEmpty &&
                self.app.frame.contains(frame) && self.app.navigationBars.element(boundBy: 0).frame.contains(frame)
        }, object: app)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            XCTFail("Expected one enabled account control in the native navigation bar: " + app.debugDescription, file: file, line: line); return
        }
        query.element(boundBy: 0).tap()
    }
    func testRelatedTopicOpensExactLegacyReadAndReopensAfterBack() {
        launch("relatedTopic")
        tapRelatedFixturePost()
        reveal(app.buttons["square.openRelatedTopic"])
        XCTAssertTrue(app.staticTexts["Synthetic linked topic 31"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Post details"].waitForExistence(timeout: 5))
        reveal(app.buttons["square.openRelatedTopic"])
        XCTAssertTrue(app.descendants(matching: .any)["topic.detail.content"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars["Post details"].buttons.firstMatch.tap()
        tapRelatedFixtureAccountSwitch()
        tapRelatedFixturePost()
        XCTAssertTrue(app.navigationBars["Post details"].waitForExistence(timeout: 5))
    }
    func testCommunityTopicReferenceAndMissingLegacyAssociationRemainSeparate() {
        launch("relatedCommunity")
        reveal(app.buttons["square.row.702"])
        reveal(app.buttons["square.openRelatedTopic"])
        XCTAssertTrue(app.staticTexts["Synthetic linked topic 32"].waitForExistence(timeout: 10))
        app.terminate(); launch("relatedMissing")
        tapRelatedFixturePost()
        XCTAssertTrue(app.descendants(matching: .any)["square.detailPost"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["square.openRelatedTopic"].exists)
    }
    func testUnavailableRelatedTopicKeepsPostAccessibleAfterBack() {
        launch("relatedUnavailable", chinese: true)
        tapRelatedFixturePost()
        reveal(app.buttons["square.openRelatedTopic"])
        XCTAssertTrue(app.staticTexts["此路线暂不可查看"].waitForExistence(timeout: 10))
        let retry = app.buttons["重试"]
        reveal(retry)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["square.detailPost"].firstMatch.waitForExistence(timeout: 5))
        reveal(app.buttons["square.openRelatedTopic"])
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
    }
}
