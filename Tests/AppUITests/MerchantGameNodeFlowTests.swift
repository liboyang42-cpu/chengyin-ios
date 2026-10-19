import XCTest

/// Synthetic offline fixtures only; integrate as --uitesting-module merchant-city-npc --w2-19-page gameNode.
final class MerchantGameNodeFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "running", chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US",
                               "--uitesting-module", "merchant-city-npc", "--w2-19-page", "gameNode", "--w2-19-scenario", scenario]
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
    }
    func testRunningStationShowsHeroRunbookAndRecap() {
        launch()
        XCTAssertTrue(app.staticTexts["Sample dock station"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["gameNode.status"].label, "Running")
        XCTAssertTrue(app.staticTexts["Open for players · 2 to verify"].exists)
        XCTAssertTrue(app.staticTexts["How to host this station"].exists)
        XCTAssertTrue(app.staticTexts["Sample: confirm the shown number only"].exists)
        reveal(app.staticTexts["Players arrived"])
        XCTAssertTrue(app.staticTexts["No confirmed actions since opening this page"].exists)
        XCTAssertFalse(app.buttons["gameNode.accept"].exists)
    }
    func testAcceptRequiresConfirmationAndRecordsReceipt() {
        launch("invited")
        let accept = app.buttons["gameNode.accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10)); accept.tap()
        let alert = app.alerts["Accept this station invitation?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Accept invitation"].tap()
        XCTAssertTrue(app.staticTexts["Preparation checklist"].waitForExistence(timeout: 10))
        reveal(app.otherElements["gameNode.receipt.STATION_ACCEPT"])
    }
    func testUncertainWriteLocksUntilReceiptReadback() {
        launch("uncertain")
        let accept = app.buttons["gameNode.accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10)); accept.tap()
        app.alerts.firstMatch.buttons["Accept invitation"].tap()
        XCTAssertTrue(app.staticTexts["Action result pending confirmation"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["gameNode.unknown.retry"].exists)
        app.buttons["gameNode.unknown.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Preparation checklist"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Action result pending confirmation"].exists)
    }
    func testRestoredPendingWriteHasNoBlindRetry() {
        launch("restored")
        XCTAssertTrue(app.staticTexts["The last action result is pending. Check the result first."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["gameNode.unknown.retry"].exists)
        app.buttons["gameNode.unknown.confirm"].tap()
        XCTAssertFalse(app.staticTexts["Action result pending confirmation"].waitForExistence(timeout: 3))
    }
    func testChinesePauseWithoutFallbackAsksFirst() {
        launch("running", chinese: true)
        let pause = app.buttons["gameNode.pause"]
        reveal(pause); pause.tap()
        XCTAssertTrue(app.staticTexts["暂停后玩家端将立即看到本站不可接待"].waitForExistence(timeout: 5))
        app.buttons["gameNode.reason.STAFF"].tap()
        app.buttons["gameNode.pause.date"].tap()
        XCTAssertTrue(app.staticTexts["选了备用方案，玩家会被引导到那一站；不选则只显示本站暂停。"].exists)
        app.buttons["gameNode.pause.submit"].tap()
        let alert = app.alerts["不设备用方案，直接暂停？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["确认暂停"].tap()
        XCTAssertTrue(app.staticTexts["暂停信息"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["gameNode.status"].label, "已暂停")
    }
    func testFocusPauseOpensSheet() {
        launch("focusPause")
        XCTAssertTrue(app.staticTexts["Players will immediately see this station as not open"].waitForExistence(timeout: 10))
    }
    func testCheckinCodeShowsCountdownAndCloses() {
        launch()
        let checkin = app.buttons["gameNode.checkin"]
        reveal(checkin); checkin.tap()
        XCTAssertTrue(app.staticTexts["Station check-in code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["gameNode.checkin.countdown"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["QR image unavailable"].exists)
        app.buttons["gameNode.checkin.close"].tap()
        XCTAssertFalse(app.staticTexts["Station check-in code"].waitForExistence(timeout: 2))
    }
    func testStatesEmptyNetworkDeniedAndInvalidFallback() {
        launch("empty")
        XCTAssertTrue(app.staticTexts["Station invitations from a club or organiser appear here."].waitForExistence(timeout: 10))
        app.terminate(); launch("error")
        XCTAssertTrue(app.staticTexts["Couldn't load station status"].waitForExistence(timeout: 10))
        app.terminate(); launch("denied", chinese: true)
        XCTAssertTrue(app.staticTexts["暂时不能查看本站"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["当前商家不负责本场站点"].exists)
        app.terminate(); launch("invalidFallback")
        XCTAssertTrue(app.staticTexts["Station data is incomplete. Try again later."].waitForExistence(timeout: 10))
        app.terminate(); launch("missingActivity")
        XCTAssertTrue(app.staticTexts["Page details are incomplete. Open it again from the merchant project card."].waitForExistence(timeout: 10))
    }
    func testReadOnlyCompositionDisablesWrites() {
        launch("readOnly")
        XCTAssertTrue(app.staticTexts["gameNode.writesDisabled"].waitForExistence(timeout: 10))
        let pause = app.buttons["gameNode.pause"]
        reveal(pause)
        XCTAssertFalse(pause.isEnabled)
    }
    func testMultipleStationsPreselectRequestedNode() {
        launch("multi")
        XCTAssertTrue(app.staticTexts["Sample clock station"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["gameNode.accept"].exists)
    }
    func testEntriesFilterByTopicAndAskToChooseSession() {
        launch("entries", chinese: true)
        XCTAssertTrue(app.staticTexts["选择场次"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["gameNode.entries.71"].exists)
        XCTAssertTrue(app.buttons["gameNode.entries.72"].exists)
        XCTAssertFalse(app.buttons["gameNode.entries.73"].exists)
    }
}
