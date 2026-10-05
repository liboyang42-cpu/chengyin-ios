import XCTest

/// Requires the composition root's home-feed fixture route; these are simulator tests, not Linux checks.
final class HomeFeedFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content") {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "home-feed", "--uitesting-home-feed-scenario", scenario]
        app.launch()
    }
    private func reveal(_ element: XCUIElement) {
        // A tall card can be reported hittable when only its top edge is visible.
        // Bring its activation point clear of the navigation bar and bottom safe area.
        for _ in 0..<12 {
            if element.exists && element.isHittable {
                let top = app.navigationBars.firstMatch.frame.maxY
                if element.frame.midY > top + 12 && element.frame.midY < app.frame.maxY - 80 { return }
                if element.frame.midY <= top + 12 { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, app.debugDescription); XCTAssertTrue(element.isHittable, app.debugDescription)
        XCTAssertLessThan(element.frame.midY, app.frame.maxY - 80, app.debugDescription)
    }
    func testTypedDestinationsAndPriceCurrencyDisclosure() {
        launch()
        let route = app.buttons["homeFeed.recommended.topic.7"]
        XCTAssertTrue(route.waitForExistence(timeout: 30))
        attachFixtureScreenshot(self,app:app,name:"Home feed initial content")
        route.tap()
        XCTAssertTrue(app.staticTexts["homeFeed.destination.topic"].waitForExistence(timeout: 15))
        app.navigationBars.buttons.firstMatch.tap()
        let activity = app.buttons["homeFeed.nearby.activity.7"]; reveal(activity); activity.tap()
        XCTAssertTrue(app.staticTexts["homeFeed.destination.activity"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(app.staticTexts["homeFeed.destination.activity"].label, "Synthetic activity destination 7")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Currency not provided"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Buy"].exists); XCTAssertFalse(app.buttons["Start playing"].exists)
    }
    func testPageFailureRetriesAndDuplicateFullPageStillPaginates() {
        launch("retry")
        let retry = app.buttons["homeFeed.retry.page"]; reveal(retry); retry.tap()
        let row = app.buttons["homeFeed.stream.topic.7"]; reveal(row)
        XCTAssertEqual(app.buttons.matching(identifier: "homeFeed.stream.topic.7").count, 1)
        let more = app.buttons["homeFeed.loadMore"]; reveal(more); more.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: more)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }
    func testEmptyStateIsNotAnError() {
        launch("empty")
        let empty = app.descendants(matching: .any)["homeFeed.empty"].firstMatch
        // Static empty-state containers need visibility/existence, not a tappable activation point.
        for _ in 0..<12 { if empty.exists { break }; app.swipeUp() }
        XCTAssertTrue(empty.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["homeFeed.retry.page"].exists)
    }
}
