import XCTest

/// Additional presentation checks on the unchanged synthetic fixture. Not live evidence.
final class GrowthNormalEntryPresentationTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String, language: String = "en", large: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
            "--uitesting-module", "growthCenter", "--uitesting-growth-scenario", scenario]
        if large { app.launchArguments += ["--uitesting-large-text", "--uitesting-dark"] }
        app.launch()
    }
    private func reveal(_ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription); XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    func testEnglishEmptyRecordsAreExplicitWithoutInventedMissionAction() {
        launch("empty")
        reveal(app.staticTexts["growth.completed.empty"])
        reveal(app.staticTexts["growth.missions.empty"])
        XCTAssertFalse(app.buttons["growth.mission.complete"].exists)
        XCTAssertFalse(app.buttons["growth.checkin"].exists)
    }
    func testChineseLargeTypeReadOnlyEmptyStatesRemainReachable() {
        launch("empty", language: "zh-Hans", large: true)
        assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility3")
        reveal(app.staticTexts["暂无已完成活动记录"])
        reveal(app.staticTexts["暂无成长任务"])
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let refresh = app.buttons["growth.refresh"]
        XCTAssertTrue(refresh.exists)
        refresh.tap()
        reveal(app.staticTexts["暂无已完成活动记录"])
    }
    func testKnownCheckinsAndStreakStayAvailableAcrossNativeBoardReturn() {
        launch("content")
        let checkins = app.descendants(matching: .any)["growth.checkins"].firstMatch
        reveal(checkins)
        for _ in 0..<4 { app.swipeDown() }
        let board = app.buttons["growth.openLeaderboard"]; reveal(board); board.tap()
        XCTAssertTrue(app.navigationBars["Leaderboard"].waitForExistence(timeout: 5))
        app.navigationBars["Leaderboard"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Growth center"].waitForExistence(timeout: 5))
        reveal(checkins)
        reveal(app.descendants(matching: .any)["growth.streak"].firstMatch)
    }
}
