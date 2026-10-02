import XCTest

/// Authored integration tests. Host must mount ClubCommunityFixture under this flag.
/// Apple simulator/build/runtime: NOT_RUN in this Linux delivery.
final class ClubCommunityUITests: XCTestCase {
    private func app(_ locale: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--club-community-fixture", "-AppleLanguages", "(\(locale))", "-AppleLocale", locale]
        app.launch(); return app
    }
    func testFeedCommentAndHistoryNavigation() {
        let app = app()
        XCTAssertTrue(app.otherElements["club.community.post.20"].waitForExistence(timeout: 5))
        app.buttons["Comments"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["club.community.comment.30"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Edit history"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Previous public content"].waitForExistence(timeout: 5))
    }
    func testComposerCancelAndImmutableReview() {
        let app = app()
        app.buttons["club.community.compose"].tap()
        let content = app.textViews["club.community.content"]
        XCTAssertTrue(content.waitForExistence(timeout: 5)); content.tap(); content.typeText("Offline draft")
        app.buttons["club.community.reviewDraft"].tap()
        XCTAssertTrue(app.buttons["club.community.confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Offline draft"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["club.community.confirm"].exists)
    }
    func testChineseAccessibleComposer() {
        let app = app("zh-Hans")
        XCTAssertTrue(app.buttons["club.community.compose"].waitForExistence(timeout: 5))
        app.buttons["club.community.compose"].tap()
        XCTAssertTrue(app.textViews["club.community.content"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
    }
}
