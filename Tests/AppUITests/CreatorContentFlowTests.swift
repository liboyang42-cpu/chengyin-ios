import XCTest
final class CreatorContentFlowTests: XCTestCase {
    private func launch(_ flags: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "creatorContent"] + flags
        app.launch(); return app
    }
    func testPublishedContentAndSourceDestination() {
        let app = launch(); app.buttons["creatorContent.openProjects"].tap()
        let row = app.buttons["creatorContent.project.topic:301"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertEqual(app.staticTexts["creatorContent.fixture.destination"].label, "topic:301")
        XCTAssertTrue(app.staticTexts["creatorContent.truncated"].exists)
    }
    func testCreatorMetricsPreserveMoneyString() {
        let app = launch(); app.buttons["creatorContent.openCenter"].tap()
        XCTAssertTrue(app.staticTexts["creatorContent.status"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["creatorContent.status"].label, "Approved creator")
        app.swipeUp(); XCTAssertTrue(app.staticTexts["001.2300"].exists)
    }
    func testRejectedCreatorExplainsResubmissionBlock() {
        let app = launch(["--creator-rejected"]); app.buttons["creatorContent.openCenter"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic rejection reason"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The current service does not accept repeat applications after rejection."].exists)
    }
    func testFailureKeepsRetryActionSeparate() {
        let app = launch(["--creator-failure"]); app.buttons["creatorContent.openProjects"].tap()
        XCTAssertTrue(app.buttons["creatorContent.retry"].waitForExistence(timeout: 5))
        app.buttons["creatorContent.retry"].tap()
        XCTAssertTrue(app.buttons["creatorContent.retry"].exists)
        XCTAssertTrue(app.staticTexts["creatorContent.issue"].exists)
    }
    func testSignOutRemovesPrivateRows() {
        let app = launch(); app.buttons["creatorContent.openProjects"].tap()
        XCTAssertTrue(app.buttons["creatorContent.project.topic:301"].waitForExistence(timeout: 5))
        app.buttons["creatorContent.fixture.signOut"].tap(); app.buttons["creatorContent.openProjects"].tap()
        XCTAssertTrue(app.staticTexts["creatorContent.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["creatorContent.project.topic:301"].exists)
    }
}
