import XCTest

final class OfficialActionUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--official-action-fixture", "-AppleLanguages", "(en)"]
        app.launch(); return app
    }
    func testPublishReviewImmutableAndOffline() {
        let app = launch(); app.buttons["officialAction.openPublish"].tap()
        let title = app.textFields["officialAction.title"]; XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap(); title.typeText("Synthetic event")
        app.swipeUp(); app.buttons["officialAction.reviewPublish"].tap()
        XCTAssertTrue(app.staticTexts["officialAction.reviewPayload"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["officialAction.confirm"].isEnabled)
    }
    func testBroadcastCannotReviewImplicitAudience() {
        let app = launch(); app.buttons["officialAction.openBroadcast"].tap(); app.swipeUp()
        XCTAssertFalse(app.buttons["officialAction.reviewBroadcast"].isEnabled)
    }
    func testDraftSurvivesReviewDismissal() {
        let app = launch(); app.buttons["officialAction.openPublish"].tap()
        let title = app.textFields["officialAction.title"]; title.tap(); title.typeText("Synthetic draft")
        app.swipeUp(); app.buttons["officialAction.reviewPublish"].tap()
        app.buttons["Close"].tap(); app.swipeDown()
        XCTAssertEqual(title.value as? String, "Synthetic draft")
    }
}
