import XCTest

/// Real section/state machine in the unchanged offline opening fixture.
final class PlayOpeningActionAccessibilityFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playOpening",
            "--play-opening-scenario", scenario, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); return app
    }
    private func depart(_ app: XCUIApplication) {
        let matches = app.buttons.matching(identifier: "playx.opening.depart")
        XCTAssertTrue(matches.element.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "playx.opening").count, 0)
        XCTAssertTrue(matches.element.isHittable && matches.element.isEnabled)
        matches.element.tap()
    }
    func testNotReadyRetainsDistinctDepartureIdentityAndBlocksConfirmation() {
        let app = launch("notReady"); defer { app.terminate() }
        depart(app)
        XCTAssertTrue(app.staticTexts["playx.opening.finishFirst"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["playx.opening.depart"].exists)
        XCTAssertFalse(app.buttons["playx.opening.confirm"].exists)
        XCTAssertFalse(app.staticTexts["playx.opening.departed"].exists)
    }
    func testReviewActionsKeepDistinctIdentitiesAndCancelWithoutDeparture() {
        let app = launch("ready"); defer { app.terminate() }
        depart(app)
        let confirm = app.buttons["playx.opening.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["playx.opening.cancel"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "playx.opening").count, 0)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Synthetic opening confirmation identities"
        tree.lifetime = .keepAlways; add(tree)
        app.buttons["playx.opening.cancel"].tap()
        XCTAssertTrue(app.buttons["playx.opening.depart"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(confirm.exists)
        XCTAssertFalse(app.staticTexts["playx.opening.departed"].exists)
    }
}
