import XCTest

/// Synthetic offline fixtures only; integrate --uitesting-module merchant-city-npc --w2-19-page playMerchant
/// -> PlayStoreDayMerchantFixtureHost(scenario:).
final class PlayStoreDayMerchantFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "normal", chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US",
                               "--uitesting-module", "merchant-city-npc", "--w2-19-page", "playMerchant", "--w2-19-scenario", scenario]
        app.launch()
    }
    private var primary: XCUIElement { app.buttons["storeDayPage.cta.primary"] }
    private var feedback: XCUIElement { app.staticTexts["storeDayPage.feedback"] }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
    }
    private func waitLabel(_ element: XCUIElement, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", label)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 8), .completed, app.debugDescription, file: file, line: line)
    }

    func testArrivalQuizPhotoAndScopedConsentHandOff() {
        launch()
        XCTAssertTrue(primary.waitForExistence(timeout: 10)); waitLabel(primary, "Scan store code")
        XCTAssertTrue(app.staticTexts["Not yet arrived"].exists)
        XCTAssertTrue(app.otherElements["storeDayPage.step.photo"].exists || app.staticTexts["storeDayPage.step.photo"].exists)
        primary.tap()
        let submitArrival = app.buttons["Submit arrival record"]
        XCTAssertTrue(submitArrival.waitForExistence(timeout: 5)); submitArrival.tap()
        let option = app.buttons["storeDayPage.game.option.B"]
        XCTAssertTrue(option.waitForExistence(timeout: 8), "arrival with a configured quiz opens the game sheet"); option.tap()
        app.buttons["storeDayPage.game.submit"].tap()
        let result = app.staticTexts["storeDayPage.game.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); XCTAssertTrue(result.label.contains("+9 exploration points"), result.label)
        app.buttons["storeDayPage.game.close"].tap()
        let takePhoto = app.buttons["storeDayPage.task.photo"]
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 5)); takePhoto.tap()
        let submitPhoto = app.buttons["Submit photo proof"]
        XCTAssertTrue(submitPhoto.waitForExistence(timeout: 5)); submitPhoto.tap()
        waitLabel(feedback, "Arrival photo recorded. You can show the redemption code to staff.")
        waitLabel(primary, "Show redemption code"); primary.tap()
        XCTAssertTrue(app.alerts["Authorize this store only"].waitForExistence(timeout: 5))
        app.alerts.buttons["Agree and continue"].tap()
        XCTAssertTrue(app.staticTexts["storeDayPage.fixture.verification"].waitForExistence(timeout: 5))
        attachFixtureScreenshot(self, app: app, name: "Store day merchant consent hand-off")
    }
    func testChineseUncertainArrivalIsReadBackNotResent() {
        launch("uncertain", chinese: true)
        XCTAssertTrue(primary.waitForExistence(timeout: 10)); waitLabel(primary, "扫描门店码")
        primary.tap()
        let submit = app.buttons["提交到店记录"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5)); submit.tap()
        XCTAssertTrue(app.staticTexts["storeDayPage.game.question"].waitForExistence(timeout: 8))
        app.buttons["关闭面板"].tap()
        waitLabel(feedback, "刚才那一步已经记下了")
        waitLabel(primary, "拍摄到店凭证")
        attachFixtureScreenshot(self, app: app, name: "Chinese store day readback")
    }
    func testStillUnknownKeepsLockAndOnlyRechecks() {
        launch("stillUnknown")
        XCTAssertTrue(primary.waitForExistence(timeout: 10)); primary.tap()
        app.buttons["Submit arrival record"].tap()
        waitLabel(primary, "Result pending · tap to check")
        XCTAssertTrue(app.buttons["storeDayPage.degraded"].waitForExistence(timeout: 5))
        primary.tap()
        waitLabel(primary, "Result pending · tap to check")
    }
    func testEmptyErrorAndSignedOutStates() {
        for (scenario, id) in [("empty", "notFound"), ("error", "failed"), ("permission", "signedOut")] {
            launch(scenario)
            XCTAssertTrue(app.otherElements["storeDayPage.state." + id].waitForExistence(timeout: 10), scenario)
            XCTAssertFalse(primary.exists, scenario)
            app.terminate()
        }
    }
    func testVerificationWithoutTicketShowsSourceCopy() {
        launch("noTicket")
        XCTAssertTrue(primary.waitForExistence(timeout: 10)); waitLabel(primary, "Show redemption code"); primary.tap()
        waitLabel(feedback, "Open this from your ticket wallet to show the redemption code")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testConsentedStoreCanWithdraw() {
        launch("consented", chinese: true)
        let revoke = app.buttons["storeDayPage.consent.revoke"]; reveal(revoke); revoke.tap()
        let confirm = app.sheets.buttons["撤回授权"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        waitLabel(feedback, "已撤回当前门店授权，门店名单将不再显示你")
        XCTAssertFalse(app.buttons["storeDayPage.consent.revoke"].exists)
    }
    func testDegradedAndRedeemedStates() {
        launch("degraded")
        XCTAssertTrue(app.buttons["storeDayPage.degraded"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["There is a queue. Consider another store first."].exists)
        app.terminate()
        launch("redeemed")
        XCTAssertTrue(primary.waitForExistence(timeout: 10)); waitLabel(primary, "Redeemed"); XCTAssertFalse(primary.isEnabled)
    }
    func testDisabledWritesAndMissingDeviceExplainInsteadOfSending() {
        launch("disabled")
        XCTAssertTrue(primary.waitForExistence(timeout: 10)); primary.tap()
        waitLabel(feedback, "On-site records are not yet connected in the app. Refresh to see recorded status.")
        XCTAssertFalse(app.buttons["Submit arrival record"].exists)
        app.terminate()
        launch("noDevice")
        XCTAssertTrue(primary.waitForExistence(timeout: 10)); primary.tap()
        waitLabel(feedback, "Scanning and photo capture are not available on this device")
    }
}
