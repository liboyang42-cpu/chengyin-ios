import XCTest
final class MerchantNPCFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch() -> XCUIApplication { let app = XCUIApplication(); app.launchArguments = ["--merchant-npc-fixture"]; runningApp = app; app.launch(); return app }
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
        let app = launch()
        let chat = app.buttons["merchantNPC.fixture.chat"]
        // Capture the unresolved first navigation boundary without a second tap,
        // added wait, or changes to the privacy invalidation path.
        attachFixtureScreenshot(self, app: app, name: "Merchant NPC before first chat entry")
        let exists = chat.exists
        let entryState = "exists=\(exists); enabled=\(exists && chat.isEnabled); hittable=\(exists && chat.isHittable); frame=\(exists ? chat.frame : .zero); appFrame=\(app.frame)"
        let entryEvidence = XCTAttachment(string: entryState + "\n" + app.debugDescription)
        entryEvidence.name = "Merchant NPC first entry accessibility and geometry"
        entryEvidence.lifetime = .keepAlways
        add(entryEvidence)
        chat.tap()
        let input = app.textFields["merchantNPC.input"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Private unsent")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5), app.debugDescription)
        app.activate()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Private unsent"].exists)
        XCTAssertFalse(app.staticTexts["merchantNPC.reply"].exists)
    }
}
