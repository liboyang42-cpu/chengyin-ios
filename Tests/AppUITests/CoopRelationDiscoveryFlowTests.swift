import XCTest

final class CoopRelationDiscoveryFlowTests: XCTestCase {
    private var app: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    private func launch(_ scenario: String = "mixed", language: String = "en", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--cooperation-flow-fixture", "--relation-discovery-fixture", "--relation-scenario", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if large { app.launchArguments += ["--uitesting-large-text", "--uitesting-reduce-motion"] }
        app.launch(); self.app = app
        let entry = app.buttons["coopflow.route.coopflow.relations"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.segmentedControls["cooprelation.tabs"].waitForExistence(timeout: 5))
        return app
    }
    func testMixedDiscoveryOpensOwnerAndClubProfilesAndReturnsToSelectedTab() {
        let app = launch()
        let merchant = app.buttons["cooprelation.open.merchants.0"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 5)); merchant.tap()
        XCTAssertTrue(app.staticTexts["Public owner 41"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cooprelation.fixture.profileReads"].label, "1:0")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.segmentedControls["cooprelation.tabs"].buttons["Clubs"].tap()
        let club = app.buttons["cooprelation.open.clubs.0"]
        XCTAssertTrue(club.waitForExistence(timeout: 5)); club.tap()
        XCTAssertTrue(app.staticTexts["Public club 9"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.openManagement"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["cooprelation.open.clubs.0"].waitForExistence(timeout: 5))
    }
    func testPartialIdentityRemainsNoninteractiveAndRefreshDoesNotReadProfiles() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["cooprelation.partial"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cooprelation.open.merchants.1"].exists)
        XCTAssertTrue(app.staticTexts["Missing owner"].exists)
        app.buttons["cooprelation.refresh"].tap()
        XCTAssertTrue(app.buttons["cooprelation.open.merchants.0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cooprelation.fixture.profileReads"].label, "0:0")
        XCTAssertFalse(app.buttons["coopflow.invite.reply"].exists)
    }
    func testClubsOnlyAndEmptyTabsHaveHonestEmptyStates() {
        let app = launch("clubs")
        XCTAssertTrue(app.staticTexts["cooprelation.empty"].waitForExistence(timeout: 5))
        app.segmentedControls["cooprelation.tabs"].buttons["Clubs"].tap()
        XCTAssertTrue(app.buttons["cooprelation.open.clubs.0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["cooprelation.empty"].exists)
    }
    func testRetryAndSessionReplacementClearPushedProfile() {
        let app = launch("retry")
        XCTAssertTrue(app.staticTexts["cooprelation.failed"].waitForExistence(timeout: 5))
        app.buttons["cooprelation.refresh"].tap()
        let merchant = app.buttons["cooprelation.open.merchants.0"]
        XCTAssertTrue(merchant.waitForExistence(timeout: 5)); merchant.tap()
        XCTAssertTrue(app.staticTexts["Public owner 41"].waitForExistence(timeout: 5))
        app.buttons["cooprelation.fixture.replace"].tap()
        XCTAssertTrue(app.buttons["cooprelation.open.merchants.0"].waitForExistence(timeout: 5))
        app.buttons["cooprelation.fixture.signOut"].tap()
        XCTAssertFalse(app.buttons["cooprelation.open.merchants.0"].exists)
        XCTAssertFalse(app.staticTexts["Public owner 41"].exists)
    }
    func testChineseMaximumTextPreservesTabsAndDisplayOnlyContext() {
        let app = launch(language: "zh-Hans", large: true)
        XCTAssertTrue(app.staticTexts["Synthetic topic context"].waitForExistence(timeout: 5))
        app.segmentedControls["cooprelation.tabs"].buttons["俱乐部"].tap()
        let club = app.buttons["cooprelation.open.clubs.0"]
        XCTAssertTrue(revealFixtureElement(club, in: app)); club.tap()
        XCTAssertTrue(app.staticTexts["Public club 9"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["context.coop.new"].exists)
    }
}
