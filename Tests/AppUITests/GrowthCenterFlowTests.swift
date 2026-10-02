import XCTest

/// Offline only. Register ModuleFixture.growthCenter before running these in the app target.
final class GrowthCenterFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", language: String = "en", extra: [String] = []) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-module", "growthCenter", "--uitesting-growth-scenario", scenario] + extra
        app.launch()
    }
    private func matchingText(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    private func expectPoints(_ value: String) {
        let points = app.descendants(matching: .any)["growth.points"].firstMatch
        XCTAssertTrue(points.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(points.label, "Current points")
        XCTAssertEqual(points.value as? String, value)
    }
    private func openBoard() {
        let link = app.buttons["growth.openLeaderboard"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), app.debugDescription); link.tap()
    }
    private func reveal(_ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription); XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    func testCenterBoardBackAndRefresh() {
        launch()
        expectPoints("640")
        XCTAssertFalse(app.staticTexts["700"].exists)
        openBoard()
        XCTAssertTrue(matchingText("Sample North").waitForExistence(timeout: 5))
        app.buttons["growth.board.refresh"].tap()
        XCTAssertTrue(matchingText("Sample North").waitForExistence(timeout: 5))
        app.navigationBars["Leaderboard"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Growth center"].waitForExistence(timeout: 5))
        openBoard()
        XCTAssertTrue(matchingText("Sample North").waitForExistence(timeout: 5))
    }
    func testMetricAndPeriodFiltersChangeIndependentParameters() {
        launch("slowFilters"); openBoard()
        app.buttons["growth.board.metric"].tap(); app.buttons["Growth"].tap()
        XCTAssertTrue(matchingText("Sample EXP North").waitForExistence(timeout: 5))
        app.buttons["growth.board.period"].tap(); app.buttons["This week"].tap()
        XCTAssertTrue(matchingText("Sample weekly South").waitForExistence(timeout: 5))
        XCTAssertTrue(matchingText("Sample EXP North").exists)
    }
    func testPartialSourceFailureDoesNotClaimEmptyBadgesOrZeroGrowth() {
        launch("partialCenter")
        expectPoints("640")
        XCTAssertFalse(app.staticTexts["No badges yet"].exists)
        let unavailable = app.staticTexts["This growth information is temporarily unavailable"]
        reveal(unavailable)
        XCTAssertFalse(app.staticTexts["Sample explorer badge"].exists)
    }
    func testMissingRankIsNeutralAndFullBoardOmitsPersonalRankRow() {
        launch("unranked")
        let rank = app.descendants(matching: .any)["growth.myRank"].firstMatch
        XCTAssertTrue(rank.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(rank.value as? String, "Not ranked yet")
        expectPoints("640")
        openBoard()
        XCTAssertTrue(matchingText("Sample North").waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["growth.board.me.0"].exists)
        XCTAssertFalse(matchingText("Sample me").exists)
    }
    func testEmptyGuestFailureAndConfigurationAreDistinct() {
        for (scenario, message) in [("empty", "No badges yet"), ("guest", "Sign in to see your growth and rankings"), ("unconfigured", "Growth service is not configured"), ("failure", "This growth information is temporarily unavailable"), ("unauthorized", "Sign in to see your growth and rankings")] {
            launch(scenario)
            reveal(app.staticTexts[message])
            XCTAssertFalse(app.staticTexts["Sample explorer badge"].exists)
            if scenario != "empty" { XCTAssertFalse(app.staticTexts["No badges yet"].exists) }
            app.terminate()
        }
    }
    func testSessionChangeClearsPrivateBoardAndNavigation() {
        launch("sessionChange"); openBoard()
        XCTAssertTrue(matchingText("Sample North").waitForExistence(timeout: 10))
        app.buttons["growth.fixture.signOut"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to see your growth and rankings"].waitForExistence(timeout: 5))
        XCTAssertFalse(matchingText("Sample North").exists); XCTAssertFalse(app.descendants(matching: .any)["growth.points"].firstMatch.exists)
    }
    func testChineseAndAccessibilityLayoutsRemainReachable() {
        launch(language: "zh-Hans", extra: ["--uitesting-dark", "--uitesting-large-text"])
        XCTAssertTrue(app.navigationBars["成长中心"].waitForExistence(timeout: 10))
        let board = app.buttons["growth.openLeaderboard"]; reveal(board)
        XCTAssertGreaterThanOrEqual(board.frame.height, 44)
        board.tap()
        XCTAssertTrue(app.navigationBars["完整排行榜"].waitForExistence(timeout: 5))
        reveal(app.buttons["growth.board.metric"])
        attachFixtureScreenshot(self, app: app, name: "Growth leaderboard Chinese large text dark mode")
    }
}
