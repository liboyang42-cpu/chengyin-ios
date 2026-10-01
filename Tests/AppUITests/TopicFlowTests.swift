import XCTest

/// Requires the integration host to add ModuleFixture.topic -> TopicFixtureHostView.
final class TopicFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self,app:app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content") {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "topic", "--uitesting-topic-scenario", scenario]
        app.launch()
    }
    private func revealAndTap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 3)
        for _ in 0..<6 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
        element.tap()
    }
    func testPagedRouteDetailChapterAndBack() {
        launch()
        revealAndTap(app.buttons["topic.loadMore"])
        XCTAssertTrue(app.buttons["topic.row.9"].waitForExistence(timeout: 5))
        revealAndTap(app.buttons["topic.row.9"])
        XCTAssertTrue(app.navigationBars["Route details"].waitForExistence(timeout: 5))
        let locked = app.descendants(matching: .any)["topic.lockedChapters"]
        for _ in 0..<4 { if locked.exists { break }; app.swipeUp() }
        XCTAssertTrue(locked.exists)
        revealAndTap(app.buttons["topic.chapter.11"])
        XCTAssertTrue(app.staticTexts["Sample first stop"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start playing"].exists)
        app.navigationBars["Chapter"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Route details"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Topic detail – synthetic locked story"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testUnavailableRouteShowsRetryWithoutContentOrPurchase() {
        launch("unavailable")
        XCTAssertTrue(app.staticTexts["This route is unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["topic.detail.content"].exists)
        revealAndTap(app.buttons["Retry"])
        XCTAssertTrue(app.staticTexts["This route is unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Buy"].exists)
    }
}
