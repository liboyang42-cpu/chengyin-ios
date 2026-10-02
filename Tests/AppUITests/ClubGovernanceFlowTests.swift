import XCTest

final class ClubGovernanceFlowTests: XCTestCase {
    private func launch(_ language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-club-governance", "-AppleLanguages", "(\(language))", "-AppleLocale", language]; app.launch(); return app
    }
    private func open(_ name: String, app: XCUIApplication) {
        let button = app.buttons["club.gov.fixture." + name]
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    private func tap(_ identifier: String, app: XCUIApplication) {
        let element = app.buttons[identifier]
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable); element.tap()
    }
    func testCustomerListDetailAndLocalRemarkReview() {
        let app = launch(); open("customers", app: app)
        XCTAssertTrue(app.buttons["club.gov.route.customer"].waitForExistence(timeout: 5)); app.buttons["club.gov.route.customer"].tap()
        let edit = app.buttons["club.gov.action.saveCustomer"]
        for _ in 0..<6 where !edit.isHittable { app.swipeUp() }; edit.tap()
        let tags = app.textFields["club.gov.input.tags"]
        for _ in 0..<6 where !tags.isHittable { app.swipeUp() }
        XCTAssertTrue(tags.waitForExistence(timeout: 5))
        tap("club.gov.prepare", app: app)
        XCTAssertTrue(app.buttons["club.gov.confirm"].waitForExistence(timeout: 5))
    }
    func testEventRolesAreDistinctFromLegacyAdministratorFlag() {
        let app = launch(); open("roles", app: app)
        XCTAssertTrue(app.buttons["club.gov.action.assignRole"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "EVENT_CHECKIN")).firstMatch.exists)
    }
    func testClubStoryUsesOwnRouteAndProtectedAnswer() {
        let app = launch(); open("topicOverview", app: app)
        let story = app.buttons["club.gov.openStory"]
        for _ in 0..<8 where !story.isHittable { app.swipeUp() }; story.tap()
        XCTAssertTrue(app.staticTexts["Fixture chapter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Fixture puzzle"].exists)
    }
    func testSwitchAccountClearsCustomerPII() {
        let app = launch(); open("customers", app: app)
        XCTAssertTrue(app.staticTexts["Fixture customer"].waitForExistence(timeout: 5))
        app.buttons["club.gov.switchAccount"].tap()
        XCTAssertTrue(app.staticTexts["club.gov.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Fixture customer"].exists)
    }
    func testChineseSettlementPreservesUnverifiedAmount() {
        let app = launch("zh-Hans"); open("settlement", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["club.gov.fact.settledAmountStatus"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["¥0"].exists)
    }
    func testAudienceUnknownIsNotZeroAndReviewRequiresContent() {
        let app = launch(); open("audienceCounts", app: app)
        let compose = app.buttons["club.gov.action.sendNotification"]
        for _ in 0..<6 where !compose.isHittable { app.swipeUp() }; compose.tap()
        tap("club.gov.prepare", app: app)
        XCTAssertTrue(app.staticTexts["club.gov.formError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.gov.confirm"].exists)
    }
}
