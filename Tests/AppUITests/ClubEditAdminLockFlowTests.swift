import XCTest

/// Mini-program club/edit (cy-scene-club-edit): administrators see the display-only note and a
/// locked membership-settings card. Synthetic fixture only; not run on Apple platforms here.
final class ClubEditAdminLockFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func open(_ scenario: String) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-club-operations", scenario]
        app.launch()
        XCTAssertTrue(app.staticTexts["club.ops.fixtureNotice"].waitForExistence(timeout: 10))
        let manage = app.buttons["club.ops.openManage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
    }
    private func reveal(_ element: XCUIElement) -> Bool {
        for _ in 0..<6 where !element.exists { app.swipeUp() }
        return element.exists
    }

    func testAdministratorSeesNoteAndLockedSettingsWithoutToggles() {
        open("admin")
        XCTAssertTrue(app.staticTexts["club.ops.adminNote"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(reveal(app.staticTexts["club.ops.locked.current"]), app.debugDescription)
        XCTAssertFalse(app.switches["club.ops.prioritySignup"].exists)
    }

    func testOwnerKeepsEditableSettingsWithoutLockCard() {
        open("owner")
        XCTAssertTrue(reveal(app.switches["club.ops.prioritySignup"]), app.debugDescription)
        XCTAssertFalse(app.staticTexts["club.ops.adminNote"].exists)
        XCTAssertFalse(app.staticTexts["club.ops.locked.current"].exists)
    }
}
