import XCTest

final class ProfileAuthorPostsRefreshFlowTests: XCTestCase {
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting", "--uitesting-profile-author-posts-refresh", "--profile-author-posts-scenario", scenario]
        app.launch(); return app
    }
    private func tap(_ id: String, in app: XCUIApplication) {
        let button = app.buttons[id]
        if !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 3)); button.tap()
    }
    func testRefreshFailureRetainsCardsAndRetryReplacesTail() {
        let app = launch("refreshFailure")
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.101"].waitForExistence(timeout: 3))
        tap("profile.postsRefresh.more", in: app)
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.201"].waitForExistence(timeout: 3))
        app.swipeDown(); tap("profile.postsRefresh.refresh", in: app)
        XCTAssertTrue(app.staticTexts["profile.postsRefresh.retained"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.201"].exists)
        tap("profile.postsRefresh.retry", in: app)
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.301"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["profile.postsRefresh.post.201"].exists)
    }
    func testEmptyRefreshReplacesPreviouslyVisiblePost() {
        let app = launch("emptyRefresh")
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.101"].waitForExistence(timeout: 3))
        tap("profile.postsRefresh.refresh", in: app)
        XCTAssertTrue(app.staticTexts["profile.postsRefresh.empty"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["profile.postsRefresh.post.101"].exists)
    }
    func testMoreFailureRetriesContinuation() {
        let app = launch("moreFailure")
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.101"].waitForExistence(timeout: 3))
        tap("profile.postsRefresh.more", in: app); tap("profile.postsRefresh.retry", in: app)
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.201"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.101"].exists)
    }
    func testSignOutRemovesCardsAndShowsExistingSignInMessage() {
        let app = launch("content")
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.101"].waitForExistence(timeout: 3))
        tap("profile.postsFixture.logout", in: app)
        XCTAssertTrue(app.staticTexts["social.profile.postsSignIn"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["profile.postsRefresh.post.101"].exists)
    }
    func testLeavingAndReturningStartsFreshFirstPage() {
        let app = launch("content")
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.101"].waitForExistence(timeout: 3))
        tap("profile.postsFixture.toggle", in: app); tap("profile.postsFixture.toggle", in: app)
        XCTAssertTrue(app.buttons["profile.postsRefresh.post.301"].waitForExistence(timeout: 3))
    }
}
