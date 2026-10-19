import XCTest

/// Synthetic club fixture only; mirrors the mini-program `pages/club/detail` tab contract.
/// Not run on Apple platforms in the authoring environment.
final class ClubDetailTabsFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func open(_ scenario: String, club: String) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-club-fixture", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["club.fixture.notice"].waitForExistence(timeout: 10))
        let row = app.buttons[club]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.staticTexts["club.detail.name"].waitForExistence(timeout: 10), app.debugDescription)
    }
    private func tab(_ key: String) -> XCUIElement { app.buttons["club.detail.tab." + key] }

    func testOwnerLandsOnPostsAndSeesManageTab() {
        open("owner", club: "club.home.owned.81")
        for key in ["posts", "events", "overview", "manage"] { XCTAssertTrue(tab(key).waitForExistence(timeout: 5), key) }
        XCTAssertTrue(tab("posts").isSelected)
        tab("overview").tap()
        XCTAssertTrue(tab("overview").isSelected)
        XCTAssertTrue(app.buttons["club.openMembers"].waitForExistence(timeout: 5), app.debugDescription)
        tab("overview").tap()
        XCTAssertTrue(tab("overview").isSelected, "Selecting the current tab is idempotent")
        tab("posts").tap()
        XCTAssertFalse(app.buttons["club.openMembers"].exists)
    }

    func testMemberHasOnlyPublicTabs() {
        open("member", club: "club.home.joined.81")
        XCTAssertTrue(tab("posts").waitForExistence(timeout: 5))
        XCTAssertTrue(tab("posts").isSelected)
        XCTAssertTrue(tab("events").exists)
        XCTAssertTrue(tab("overview").exists)
        XCTAssertFalse(tab("manage").exists)
        XCTAssertFalse(app.buttons["club.openManagement"].exists)
        tab("overview").tap()
        // This fixture host has no governance context, so the board states it is unavailable.
        let board = app.descendants(matching: .any)["club.detail.leaderboard.unavailable"]
        for _ in 0..<4 where !board.exists { app.swipeUp() }
        XCTAssertTrue(board.exists, app.debugDescription)
    }
}
