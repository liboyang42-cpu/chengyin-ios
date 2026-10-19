import XCTest

/// Mini-program club/create sends non-hosts to club/apply. Synthetic fixtures only;
/// not run on Apple platforms in the authoring environment.
final class ClubCreateHostApplicationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String, hostApply: Bool) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-club-operations", scenario]
            + (hostApply ? ["--uitesting-club-operations-host-apply"] : [])
        app.launch()
        XCTAssertTrue(app.staticTexts["club.ops.fixtureNotice"].waitForExistence(timeout: 10))
        let create = app.buttons["club.ops.openCreate"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
    }

    func testNonLeaderCreateLinksToHostApplicationWithoutWriting() {
        launch("ordinary", hostApply: true)
        let apply = app.buttons["club.ops.applyHost"]
        XCTAssertTrue(apply.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["club.ops.reviewProfile"].exists)
        apply.tap()
        XCTAssertFalse(apply.waitForExistence(timeout: 2) && apply.isHittable, app.debugDescription)
        XCTAssertEqual(app.staticTexts["club.ops.writeCount"].firstMatch.label, "0")
    }

    func testLeaderAtLimitHasNoApplicationLink() {
        launch("limit", hostApply: true)
        XCTAssertTrue(app.staticTexts["You already own two clubs. Manage an existing club instead."].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["club.ops.applyHost"].exists)
    }
}
