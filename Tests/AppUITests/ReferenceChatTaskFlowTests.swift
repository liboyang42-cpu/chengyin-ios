import XCTest

/// Synthetic UI scenarios. Runtime screenshots are produced only when Apple CI executes these tests.
final class ReferenceChatTaskFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func launch(_ args: [String], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + args
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, top: Bool = false) {
        XCTAssertTrue(revealFixtureElement(element, in: app, towardTop: top), app.debugDescription)
    }
    private func reviewNPC(_ app: XCUIApplication, text: String = "Draft retained / 保留草稿") {
        let input = element("shopNPC.input", app); XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(text)
        let button = app.buttons["shopNPC.reviewText"]; XCTAssertTrue(button.isHittable); button.tap()
        reveal(app.buttons["shopNPC.confirmSend"], app)
    }
    func testNPCCancelReviewRetainsDraftAndCanReopen() {
        let app = launch(["--shop-npc-fixture", "enabled"]); reviewNPC(app)
        let cancel = app.buttons["shopNPC.cancel"]; reveal(cancel, app); cancel.tap()
        XCTAssertEqual(element("shopNPC.input", app).value as? String, "Draft retained / 保留草稿")
        XCTAssertFalse(app.buttons["shopNPC.confirmSend"].exists)
        app.buttons["shopNPC.reviewText"].tap(); reveal(app.buttons["shopNPC.confirmSend"], app)
        XCTAssertFalse(app.staticTexts["Fixture reply / 测试回答"].exists)
        attachFixtureScreenshot(self, app: app, name: "NPC review reopened without transmission")
    }
    func testNPCUnknownResultRetainsReviewAndDoesNotInventReply() {
        let app = launch(["--shop-npc-fixture", "enabled", "--reference-npc-unknown"]); reviewNPC(app)
        app.buttons["shopNPC.confirmSend"].tap(); reveal(element("shopNPC.error", app), app)
        XCTAssertFalse(app.staticTexts["Fixture reply / 测试回答"].exists)
        XCTAssertTrue(app.buttons["shopNPC.confirmSend"].exists)
        XCTAssertEqual(element("shopNPC.input", app).value as? String, "Draft retained / 保留草稿")
    }
    func testNPCFailureKeepsTheExactReviewText() {
        let app = launch(["--shop-npc-fixture", "enabled", "--reference-npc-failed"]); reviewNPC(app)
        app.buttons["shopNPC.confirmSend"].tap(); reveal(element("shopNPC.error", app), app)
        XCTAssertTrue(app.staticTexts["Synthetic failure / 测试失败"].exists)
        XCTAssertFalse(app.staticTexts["Fixture reply / 测试回答"].exists)
        XCTAssertTrue(app.buttons["shopNPC.cancel"].exists)
    }
    func testNPCPendingDisablesDuplicateTransmissionAndScopeClearsPrivateText() {
        let app = launch(["--shop-npc-fixture", "enabled", "--reference-npc-pending", "--reference-npc-scope-control"]); reviewNPC(app)
        app.buttons["shopNPC.confirmSend"].tap()
        XCTAssertFalse(app.buttons["shopNPC.confirmSend"].isEnabled)
        app.buttons["referenceNPC.invalidate"].tap()
        XCTAssertFalse(app.buttons["shopNPC.confirmSend"].exists)
        XCTAssertFalse(element("shopNPC.input", app).isEnabled)
        let remainingDraft = (element("shopNPC.input", app).value as? String) ?? ""
        XCTAssertFalse(remainingDraft.contains("Draft retained"))
        XCTAssertFalse(app.staticTexts["Fixture reply / 测试回答"].exists)
    }
    func testNPCChineseMaximumTextKeyboardAndReduceMotion() {
        let app = launch(["--shop-npc-fixture", "enabled", "--uitesting-max-text", "--uitesting-reduce-motion", "--uitesting-dark"], language: "zh-Hans")
        let input = element("shopNPC.input", app); XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Long draft / 长消息")
        let done = app.buttons["shopNPC.keyboard.done"]; XCTAssertTrue(done.waitForExistence(timeout: 3)); done.tap()
        XCTAssertTrue(app.buttons["shopNPC.reviewText"].isHittable)
        XCTAssertFalse(app.buttons["shopNPC.record"].isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
        attachFixtureScreenshot(self, app: app, name: "NPC Chinese maximum text dark Reduce Motion")
    }
    func testMessageKeyboardKeepsSendActionReachable() {
        let app = launch(["--uitesting-module", "composer"])
        let input = element("message.send.input", app); XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(String(repeating: "Message text ", count: 12))
        XCTAssertTrue(app.buttons["message.send.button"].isHittable)
        app.buttons["message.send.keyboard.done"].tap()
        XCTAssertTrue(app.buttons["message.send.button"].isHittable)
        attachFixtureScreenshot(self, app: app, name: "IM long draft and pinned composer")
    }
    func testMessageUnknownIsNotAnAcceptedReceiptAndCancelRetryDoesNotSend() {
        let app = launch(["--uitesting-module", "composer", "--reference-message-unknown"])
        let input = element("message.send.input", app); XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Unknown message")
        app.buttons["message.send.button"].tap()
        XCTAssertTrue(element("message.send.issue", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("message.send.receipt", app).exists); XCTAssertFalse(input.isEnabled)
        app.buttons["message.send.retry"].tap(); app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(element("message.send.issue", app).exists)
        XCTAssertFalse(app.buttons["messaging.message.2"].exists)
    }
    func testMessageRejectedDoesNotShowAcceptedReceipt() {
        let app = launch(["--uitesting-module", "composer", "--reference-message-rejected"])
        let input = element("message.send.input", app); XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Rejected message")
        app.buttons["message.send.button"].tap()
        XCTAssertTrue(element("message.send.issue", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("message.send.receipt", app).exists); XCTAssertTrue(input.isEnabled)
    }
    func testMessagePendingDoesNotPermitDuplicateSend() {
        let app = launch(["--uitesting-module", "composer", "--reference-message-pending"])
        let input = element("message.send.input", app); XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Pending message")
        app.buttons["message.send.button"].tap()
        XCTAssertFalse(app.buttons["message.send.button"].isEnabled); XCTAssertFalse(input.isEnabled)
        XCTAssertFalse(element("message.send.receipt", app).exists)
    }
    func testMessageEarlierPageAndDetailReturnRetainHistory() {
        let app = launch(["--uitesting-module", "messaging"])
        let conversation = app.buttons["messaging.conversation.901"]; XCTAssertTrue(conversation.waitForExistence(timeout: 5)); conversation.tap()
        let earlier = app.buttons["messaging.history.earlier"]; reveal(earlier, app, top: true); earlier.tap()
        let message = app.buttons["messaging.message.1"]; reveal(message, app, top: true); message.tap()
        XCTAssertTrue(element("messaging.message.detail", app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap(); reveal(message, app, top: true)
        XCTAssertFalse(earlier.exists)
        attachFixtureScreenshot(self, app: app, name: "IM earlier history retained after detail return")
    }
    func testKnownProgressAndCurrentTaskReopenPreserveServerZero() {
        let app = launch(["--uitesting-module", "playExperience"])
        let count = app.staticTexts["referenceTask.count"]; XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "Completed 0 of 1")
        let open = app.buttons["referenceTask.open"]; reveal(open, app); open.tap()
        app.navigationBars.buttons.firstMatch.tap(); reveal(open, app, top: true); open.tap()
        app.navigationBars.buttons.firstMatch.tap(); reveal(count, app, top: true)
        XCTAssertEqual(count.label, "Completed 0 of 1")
    }
    func testUnknownTotalShowsPhaseWithoutPercentage() {
        let app = launch(["--uitesting-module", "playExperience", "--uitesting-play-experience-scenario", "referenceUnknownTotal"])
        XCTAssertTrue(app.staticTexts["referenceTask.phaseOnly"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.progressIndicators["referenceTask.progress"].exists)
        XCTAssertFalse(app.staticTexts["referenceTask.count"].exists)
        attachFixtureScreenshot(self, app: app, name: "Journey unknown denominator phase-only")
    }
    func testChineseServerCompletedHasNoCurrentAction() {
        let app = launch(["--uitesting-module", "playExperience", "--uitesting-play-experience-scenario", "referenceComplete", "--uitesting-reduce-motion", "--uitesting-large-text"], language: "zh-Hans")
        let count = app.staticTexts["referenceTask.count"]; XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "已完成 1 / 共 1")
        XCTAssertFalse(app.buttons["referenceTask.open"].exists)
        attachFixtureScreenshot(self, app: app, name: "Journey Chinese completed server snapshot reduced motion")
    }
    func testFailedTaskReadCannotShowAProgressBarOrCurrentAction() {
        let app = launch(["--uitesting-module", "playExperience", "--uitesting-play-experience-scenario", "referenceFailure"])
        XCTAssertTrue(element("playx.issue", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.progressIndicators["referenceTask.progress"].exists)
        XCTAssertFalse(app.buttons["referenceTask.open"].exists)
    }
    func testMessageAccountSwitchDoesNotRetainPrivateHistory() {
        let app = launch(["--uitesting-module", "messaging"])
        let conversation = app.buttons["messaging.conversation.901"]; XCTAssertTrue(conversation.waitForExistence(timeout: 5)); conversation.tap()
        let own = app.buttons["messaging.message.11"]; reveal(own, app, top: true)
        XCTAssertTrue(own.label.contains("9001"))
        app.navigationBars.buttons.firstMatch.tap(); app.buttons["messaging.fixture.switch"].tap()
        XCTAssertTrue(conversation.waitForExistence(timeout: 5)); conversation.tap(); reveal(own, app, top: true)
        XCTAssertTrue(own.label.contains("9002")); XCTAssertFalse(own.label.contains("9001"))
    }
    func testMerchantAIIdentityIsVisibleAndReopenStartsFresh() {
        let app = launch(["--merchant-npc-fixture"], language: "zh-Hans")
        let open = app.buttons["merchantNPC.fixture.chat"]; XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        XCTAssertTrue(app.staticTexts["商家 AI NPC"].waitForExistence(timeout: 5))
        let input = element("merchantNPC.input", app); input.tap(); input.typeText("Private draft")
        app.buttons["merchantNPC.keyboard.done"].tap(); app.navigationBars.buttons.firstMatch.tap()
        open.tap(); XCTAssertTrue(input.waitForExistence(timeout: 5))
        let draft = (input.value as? String) ?? ""
        XCTAssertFalse(draft.contains("Private draft")); XCTAssertFalse(app.staticTexts["merchantNPC.reply"].exists)
    }

}
