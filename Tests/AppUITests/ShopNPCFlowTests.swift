import XCTest
final class ShopNPCFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
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
        let app = launch(enabled: true); let input = app.textFields["shopNPC.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("private sent message")
        app.buttons["shopNPC.reviewText"].tap(); app.buttons["shopNPC.confirmSend"].tap()
        XCTAssertTrue(app.staticTexts["Fixture reply / 测试回答"].waitForExistence(timeout: 5))
        input.tap(); input.typeText(" private unsent draft")
        XCUIDevice.shared.press(.home); app.activate()
        let reviewButtons = app.buttons.matching(identifier: "shopNPC.reviewText")
        let inputs = app.textFields.matching(identifier: "shopNPC.input")
        // UIKit briefly exposes both the foreground Form and its privacy-redacted snapshot.
        // Require exactly one of each; firstMatch would hide a persistent duplicate-control bug.
        let foregroundSettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            reviewButtons.count == 1 && inputs.count == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [foregroundSettled], timeout: 5), .completed)
        XCTAssertFalse(reviewButtons.element(boundBy: 0).isEnabled)
        XCTAssertFalse(inputs.element(boundBy: 0).isEnabled)
        let remainingDraft = (inputs.element(boundBy: 0).value as? String) ?? ""
        XCTAssertFalse(remainingDraft.contains("private"))
        XCTAssertFalse(app.staticTexts["private sent message"].exists)
        XCTAssertFalse(app.staticTexts["Fixture reply / 测试回答"].exists)
        XCTAssertFalse(app.buttons["shopNPC.confirmSend"].exists)
    }
}
