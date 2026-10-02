import XCTest
final class MerchantNPCFlowTests: XCTestCase {
    private func launch() -> XCUIApplication { let app = XCUIApplication(); app.launchArguments = ["--merchant-npc-fixture"]; app.launch(); return app }
    func testMerchantChatCompleteReply() {
        let app = launch(); app.buttons["merchantNPC.fixture.chat"].tap()
        let input = app.textFields["merchantNPC.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Hello merchant")
        app.buttons["merchantNPC.send"].tap(); XCTAssertTrue(app.staticTexts["merchantNPC.reply"].waitForExistence(timeout: 5))
    }
    func testResourcesRequireConsentAndNoCapture() {
        let app = launch(); app.buttons["merchantNPC.fixture.resources"].tap()
        XCTAssertTrue(app.switches["merchantNPC.ownsVoice"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["merchantNPC.confirm"].exists)
        XCTAssertFalse(app.buttons["merchantNPC.record"].exists)
    }
    func testBackgroundClearsChat() {
        let app = launch(); app.buttons["merchantNPC.fixture.chat"].tap()
        let input = app.textFields["merchantNPC.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Private unsent")
        XCUIDevice.shared.press(.home); app.activate(); XCTAssertFalse(app.textFields["merchantNPC.input"].exists)
    }
}
