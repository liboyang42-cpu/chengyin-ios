import XCTest
final class ShopNPCFlowTests: XCTestCase {
    private func launch(enabled: Bool) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--shop-npc-fixture", enabled ? "enabled" : "disabled"]; app.launch(); return app
    }
    func testDefaultOff() { let app = launch(enabled: false); XCTAssertTrue(app.staticTexts["shopNPC.disabled"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["shopNPC.reviewText"].isEnabled) }
    func testReviewBeforeTransmission() {
        let app = launch(enabled: true); let input = app.textFields["shopNPC.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("hello")
        app.buttons["shopNPC.reviewText"].tap(); XCTAssertTrue(app.buttons["shopNPC.confirmSend"].exists); XCTAssertFalse(app.staticTexts["Fixture reply / 测试回答"].exists)
        app.buttons["shopNPC.confirmSend"].tap(); XCTAssertTrue(app.staticTexts["Fixture reply / 测试回答"].waitForExistence(timeout: 5))
    }
    func testVoiceRemainsOffInFixture() { let app = launch(enabled: true); XCTAssertTrue(app.buttons["shopNPC.record"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["shopNPC.record"].isEnabled) }
    func testBackgroundClearsConversation() {
        let app = launch(enabled: true); let input = app.textFields["shopNPC.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("private")
        XCUIDevice.shared.press(.home); app.activate(); XCTAssertFalse(app.buttons["shopNPC.reviewText"].isEnabled)
    }
}
