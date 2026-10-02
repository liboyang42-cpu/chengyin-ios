import XCTest

final class ClubEnrollmentFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-club-governance", "-AppleLanguages", "(\(language))", "-AppleLocale", language]; app.launch()
        let entry = app.buttons["club.enroll.fixture"]; XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap(); return app
    }
    func testFocusedRosterOpensTicketAndCheckinReturnsToRoster() {
        let app = launch(); XCTAssertTrue(app.buttons["club.enroll.team.91"].waitForExistence(timeout: 5))
        let checkin = app.buttons["club.enroll.checkin.121"]
        XCTAssertTrue(revealFixtureElement(checkin, in: app), app.debugDescription)
        XCTAssertTrue(checkin.waitForExistence(timeout: 5)); checkin.tap()
        XCTAssertTrue(app.descendants(matching: .any)["club.gov.fact.registrationId"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Enrollment roster"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "social.profile").firstMatch.exists)
        XCTAssertTrue(revealFixtureElement(checkin, in: app), app.debugDescription)
        XCTAssertTrue(checkin.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.gov.confirm"].exists)
    }
    func testPublicProfileIsARealDestination() {
        let app = launch(); let profile = app.buttons["club.enroll.profile.121"]
        XCTAssertTrue(revealFixtureElement(profile, in: app), app.debugDescription)
        XCTAssertTrue(profile.waitForExistence(timeout: 5)); profile.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "social.profile").firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Public profile"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "club.gov.fact.registrationId").firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Enrollment roster"].waitForExistence(timeout: 5))
    }
    func testIdentityChangeClearsRegistrantNamesInChinese() {
        let app = launch("zh-Hans"); let profile = app.buttons["club.enroll.profile.121"]
        XCTAssertTrue(revealFixtureElement(profile, in: app), app.debugDescription)
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        app.buttons["club.gov.switchAccount"].tap()
        XCTAssertFalse(app.staticTexts["Fixture attendee"].waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["club.enroll.checkin.121"].exists)
        XCTAssertFalse(profile.exists)
    }
}
