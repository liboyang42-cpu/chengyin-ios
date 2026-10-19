import XCTest

/// Offline fixture flows for the w2-10 mini-program parity states. No network, camera or writes.
final class GrowthBadgeStampParityFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ arguments: [String]) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launch()
    }
    private func matchingText(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testForbiddenGrowthReadShowsAccountAccessStateWithRetry() {
        launch(["--uitesting-module", "growthCenter", "--uitesting-growth-scenario", "denied"])
        XCTAssertTrue(matchingText("cannot view growth records").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["growth.retry"].exists)
        XCTAssertFalse(matchingText("Sign in to see your growth").exists)
    }
    func testRefreshAnnouncesOnlyBadgesLitSinceThePreviousRead() {
        launch(["--uitesting-module", "growthCenter", "--uitesting-growth-scenario", "newBadge"])
        XCTAssertTrue(app.descendants(matching: .any)["growth.points"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["growth.badges.newlyLit"].firstMatch.exists)
        app.buttons["growth.refresh"].tap()
        let status = app.descendants(matching: .any)["growth.badges.newlyLit"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(status.label.contains("Sample new badge"), status.label)
        XCTAssertFalse(status.label.contains("Sample explorer badge"), status.label)
    }
    func testLeaderboardMarksPodiumRowsAndTheViewer() {
        launch(["--uitesting-module", "growthCenter", "--uitesting-growth-scenario", "content"])
        let link = app.buttons["growth.openLeaderboard"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), app.debugDescription); link.tap()
        XCTAssertTrue(matchingText("First place").waitForExistence(timeout: 10), app.debugDescription)
        let me = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "growth.board.me.")).firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(me.label.contains("Me"), me.label)
    }
    func testForbiddenObjectCardReadIsNotARetryableFailure() {
        launch(["--uitesting-module", "objectCards"])
        XCTAssertTrue(app.buttons["objects.card.901"].waitForExistence(timeout: 5))
        app.buttons["objects.fixture.deny"].tap()
        let filter = app.descendants(matching: .any)["objects.filter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 5), app.debugDescription); filter.tap()
        let category = app.buttons["objects.category.objects.category.5"]
        XCTAssertTrue(category.waitForExistence(timeout: 5), app.debugDescription); category.tap()
        XCTAssertTrue(app.staticTexts["objects.denied"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["objects.failed"].exists)
    }
    func testStampAlbumShowsServerTotalAndEmptyCameraEntry() {
        launch(["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", "empty"])
        let open = app.buttons["roam.experience.album.open"]
        if !open.isHittable { app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["roam.experience.album.empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stamps: 0"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["roam.experience.album.openCamera"].exists, app.debugDescription)
    }
}
