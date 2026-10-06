import XCTest

/// Root integration: ModuleFixture.accountCollections -> AccountCollectionFixtureHostView.
/// All cases are synthetic and offline; no API base URL or credentials are configured.
final class AccountSavedPostCollectionFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", language: String = "en", extra: [String] = []) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-module", "accountCollections", "--uitesting-account-collection-scenario", scenario] + extra
        app.launch()
    }
    private func open(_ id: String, diagnoseNavigation: Bool = false) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        if diagnoseNavigation { logNavigationBoundary("before single tap", target: button, identifier: id) }
        button.tap()
        if diagnoseNavigation { logNavigationBoundary("after single tap", target: button, identifier: id) }
    }
    // This module is synthetic and offline. Log only the selected control and
    // navigation bars; image-only CI evidence does not retain AX attachments.
    private func logNavigationBoundary(_ phase: String, target: XCUIElement, identifier: String) {
        // A successful push removes the tapped source control. Never re-resolve it after
        // navigation: exists and the next AX query can observe different hierarchies.
        if phase == "after single tap" {
            print("ACCOUNT_COLLECTION_NAVIGATION phase=\(phase); identifier=\(identifier); targetLookup=omitted-after-navigation")
            print("ACCOUNT_COLLECTION_NAVIGATION_AX " + app.navigationBars.debugDescription)
            return
        }
        let exists = target.exists
        print("ACCOUNT_COLLECTION_NAVIGATION phase=\(phase); identifier=\(identifier); type=\(exists ? String(target.elementType.rawValue) : "absent"); exists=\(exists); enabled=\(exists && target.isEnabled); hittable=\(exists && target.isHittable); frame=\(exists ? target.frame : .zero)")
        if exists { print("ACCOUNT_COLLECTION_TARGET_AX " + target.debugDescription) }
        print("ACCOUNT_COLLECTION_NAVIGATION_AX " + app.navigationBars.debugDescription)
    }
    private func assertChineseNavigation(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let destination = app.navigationBars[title]
        let arrived = destination.waitForExistence(timeout: 5)
        logNavigationBoundary("after destination wait: " + title, target: destination, identifier: title)
        XCTAssertTrue(arrived, file: file, line: line)
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }












    func testSavedPostsAreDefaultAndOpenLegacyDetailThenReturn() {
        launch(); open("accountCollection.openFavorites")
        let first = app.buttons["accountCollection.post.801"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["accountCollection.favorite.301"].exists)
        reveal(first); first.tap()
        XCTAssertTrue(app.navigationBars["Post details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["square.detailPost"].firstMatch.waitForExistence(timeout: 5))
        open("Close")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let tabs = app.segmentedControls["accountCollection.favorites.tabs"]
        tabs.buttons["Topics"].tap()
        XCTAssertTrue(app.buttons["accountCollection.favorite.301"].waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists)
        tabs.buttons["Posts"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
    }
    func testSavedPostPageFailureRetainsRowsAndRetryDoesNotSkip() {
        launch("postPageFailure"); open("accountCollection.openFavorites")
        let more = app.buttons["accountCollection.posts.loadMore"]
        reveal(more); more.tap()
        XCTAssertTrue(app.staticTexts["Sample saved post page unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accountCollection.post.801"].exists)
        let retry = app.buttons["accountCollection.retry"]
        reveal(retry); retry.tap()
        XCTAssertTrue(app.buttons["accountCollection.post.803"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "accountCollection.post.801").count, 1)
    }
    func testSavedPostFailureDoesNotPoisonTopicCollection() {
        launch("postFailure"); open("accountCollection.openFavorites")
        XCTAssertTrue(app.staticTexts["Sample saved posts unavailable"].waitForExistence(timeout: 5))
        app.segmentedControls["accountCollection.favorites.tabs"].buttons["Topics"].tap()
        XCTAssertTrue(app.buttons["accountCollection.favorite.301"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Sample saved posts unavailable"].exists)
    }
    func testSavedPostsDistinguishEmptyFromUnavailableAndClearOnSignOut() {
        launch("empty"); open("accountCollection.openFavorites")
        XCTAssertTrue(app.descendants(matching: .any)["accountCollection.posts.empty"].firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        launch("sessionChange"); open("accountCollection.openFavorites")
        XCTAssertTrue(app.buttons["accountCollection.post.801"].waitForExistence(timeout: 5))
        open("accountCollection.fixture.signOut")
        open("accountCollection.openFavorites")
        XCTAssertTrue(app.staticTexts["Sign in to see your saved collections"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["accountCollection.post.801"].exists)
    }

}
