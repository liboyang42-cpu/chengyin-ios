import XCTest

final class DoorReferralUITests: XCTestCase {
    // Host must wire --door-referral-fixture to DoorReferralFixtureView per integration guide.
    func testOfflineFixtureNormalizesScene() {
        let app = XCUIApplication(); app.launchArguments += ["--door-referral-fixture"]; app.launch()
        XCTAssertTrue(app.staticTexts["door.fixture.normalized"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["door.fixture.normalized"].label, "abcdef0123456789abcdef0123456789")
    }
    func testInvalidSceneFixture() {
        let app = XCUIApplication(); app.launchArguments += ["--door-referral-fixture"]; app.launch()
        let field = app.textFields["door.fixture.scene"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.press(forDuration: 1.1)
        // Append makes the exact 32-hex scene invalid without clipboard or camera access.
        field.typeText("z")
        XCTAssertEqual(app.staticTexts["door.fixture.normalized"].label, "invalid")
    }
}
