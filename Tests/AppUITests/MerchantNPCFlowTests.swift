import XCTest
final class MerchantNPCFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch() -> XCUIApplication { let app = XCUIApplication(); app.launchArguments = ["--merchant-npc-fixture"]; app.launch(); return app }
    func testMerchantChatCompleteReply() {
        let app = launch(); app.buttons["merchantNPC.fixture.chat"].tap()
        let input = app.textFields["merchantNPC.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Hello merchant")
        app.buttons["merchantNPC.send"].tap(); XCTAssertTrue(app.staticTexts["merchantNPC.reply"].waitForExistence(timeout: 5))
    }
    func testResourcesRequireConsentAndNoCapture() {
        let app = launch(); app.buttons["merchantNPC.fixture.resources"].tap()
        let ownsVoice = app.switches["merchantNPC.ownsVoice"]
        for _ in 0..<10 {
            if ownsVoice.waitForExistence(timeout: 0.3) && ownsVoice.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(ownsVoice.exists, app.debugDescription)
        XCTAssertEqual(ownsVoice.value as? String, "0")
        let consent = app.switches["merchantNPC.consent"]
        XCTAssertTrue(consent.exists); XCTAssertEqual(consent.value as? String, "0")
        let enroll = app.buttons["merchantNPC.reviewEnroll"]
        for _ in 0..<4 { if enroll.exists && enroll.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(enroll.exists); XCTAssertFalse(enroll.isEnabled)
        XCTAssertFalse(app.buttons["merchantNPC.confirm"].exists)
        XCTAssertFalse(app.buttons["merchantNPC.record"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "merchantVoice.record.")).count, 0)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testBackgroundClearsChat() {
        let app = launch(); app.buttons["merchantNPC.fixture.chat"].tap()
        let input = app.textFields["merchantNPC.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Private unsent")
        XCUIDevice.shared.press(.home); app.activate(); XCTAssertFalse(app.textFields["merchantNPC.input"].exists)
    }
}
