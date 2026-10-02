import XCTest

final class ClubGovernanceFlowTests: XCTestCase {
    private func launch(_ language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--uitesting-club-governance", "-AppleLanguages", "(\(language))", "-AppleLocale", language]; app.launch(); return app
    }
    private func open(_ name: String, app: XCUIApplication) {
        let button = app.buttons["club.gov.fixture." + name]
        reveal(button, app: app)
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    private func fact(_ key: String, containing text: String, app: XCUIApplication) -> XCUIElement {
        // LabeledContent exposes its label and value together on some iOS versions.
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
            "club.gov.fact." + key, text, text)).firstMatch
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let revealed = revealFixtureElement(element, in: app)
        if !revealed { attachFixtureScreenshot(self, app: app, name: "Unreachable club governance control") }
        XCTAssertTrue(revealed, app.debugDescription)
    }
    private func tap(_ identifier: String, app: XCUIApplication) {
        let element = app.buttons[identifier]
        reveal(element, app: app)
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable); element.tap()
    }
    func testCustomerListDetailAndLocalRemarkReview() {
        let app = launch(); open("customers", app: app)
        tap("club.gov.route.customer", app: app)
        let edit = app.buttons["club.gov.action.saveCustomer"]
        reveal(edit, app: app); edit.tap()
        let tags = app.textFields["club.gov.input.tags"]
        reveal(tags, app: app)
        XCTAssertTrue(tags.waitForExistence(timeout: 5))
        tap("club.gov.prepare", app: app)
        let confirm = app.buttons["club.gov.confirm"]
        reveal(confirm, app: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    }
    func testEventRolesAreDistinctFromLegacyAdministratorFlag() {
        let app = launch(); open("roles", app: app)
        XCTAssertTrue(app.buttons["club.gov.action.assignRole"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "EVENT_CHECKIN")).firstMatch.exists)
    }
    func testClubStoryUsesOwnRouteAndProtectedAnswer() {
        let app = launch(); open("topicOverview", app: app)
        let story = app.buttons["club.gov.openStory"]
        reveal(story, app: app); story.tap()
        let chapter = fact("title", containing: "Fixture chapter", app: app)
        reveal(chapter, app: app)
        XCTAssertTrue(chapter.waitForExistence(timeout: 5))
        let puzzle = fact("title", containing: "Fixture puzzle", app: app)
        reveal(puzzle, app: app)
        XCTAssertTrue(puzzle.waitForExistence(timeout: 5))
    }
    func testSwitchAccountClearsCustomerPII() {
        let app = launch(); open("customers", app: app)
        let customer = fact("displayName", containing: "Fixture customer", app: app)
        reveal(customer, app: app)
        XCTAssertTrue(customer.waitForExistence(timeout: 5))
        app.buttons["club.gov.switchAccount"].tap()
        XCTAssertTrue(app.staticTexts["club.gov.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(customer.exists)
        XCTAssertFalse(app.buttons["club.gov.route.customer"].exists)
    }
    func testChineseSettlementPreservesUnverifiedAmount() {
        let app = launch("zh-Hans"); open("settlement", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["club.gov.fact.settledAmountStatus"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["¥0"].exists)
    }
    func testAudienceUnknownIsNotZeroAndReviewRequiresContent() {
        let app = launch(); open("audienceCounts", app: app)
        let presentingToolbar = app.toolbars.containing(.button, identifier: "club.gov.switchAccount").firstMatch
        XCTAssertTrue(presentingToolbar.waitForExistence(timeout: 5))
        XCTAssertTrue(presentingToolbar.isHittable)
        let compose = app.buttons["club.gov.action.sendNotification"]
        reveal(compose, app: app); compose.tap()
        let modalBar = app.navigationBars["Compose member notification"]
        XCTAssertTrue(modalBar.waitForExistence(timeout: 5))
        XCTAssertTrue(modalBar.isHittable)
        // Some iOS versions retain the presenter's toolbar in the modal AX tree.
        // It must not shorten the sheet's viewport while covered by that sheet.
        if presentingToolbar.exists { XCTAssertFalse(presentingToolbar.isHittable) }
        tap("club.gov.prepare", app: app)
        XCTAssertTrue(app.staticTexts["club.gov.formError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.gov.confirm"].exists)
        attachFixtureScreenshot(self, app: app, name: "Club notification rejects missing content")
    }
}
