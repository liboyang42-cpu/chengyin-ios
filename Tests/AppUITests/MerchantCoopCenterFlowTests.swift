import XCTest

/// Synthetic offline fixture: --uitesting-module merchant-city-npc --w2-19-page coopCenter.
final class MerchantCoopCenterFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "normal", chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US",
                               "--uitesting-module", "merchant-city-npc", "--w2-19-page", "coopCenter", "--w2-19-scenario", scenario]
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
    private func tab(_ title: String) { app.segmentedControls["merchantCoopCenter.tabs"].buttons[title].tap() }

    func testPlazaIsDefaultAndCardsMirrorSourceFields() {
        launch()
        XCTAssertTrue(app.buttons["merchantCoopCenter.route.detail.70"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Cooperation center"].exists)
        XCTAssertTrue(app.segmentedControls["merchantCoopCenter.tabs"].buttons["Plaza"].isSelected)
        XCTAssertTrue(app.staticTexts["City orienteering"].exists)
        XCTAssertTrue(app.staticTexts["Seats left: 3"].exists)
        XCTAssertTrue(app.staticTexts["10/12 – 10/14"].exists)
        XCTAssertTrue(app.staticTexts["◎  Sample City · 3 stops"].exists)
        XCTAssertTrue(app.staticTexts["Perk redemption · perks worth at least ¥20"].exists)
        XCTAssertTrue(app.staticTexts["Recruiting until 10/10"].exists)
        reveal(app.staticTexts["Revenue share · per-head fee up to ¥8.5 per visit"])
        XCTAssertTrue(app.staticTexts["10/20"].exists)
        reveal(app.staticTexts["Perk redemption / Traffic partnership"])
        XCTAssertTrue(app.staticTexts["Full"].exists)
        XCTAssertTrue(app.staticTexts["Closed"].exists)
        reveal(app.staticTexts["Traffic partnership · no settlement"])
        reveal(app.staticTexts["12 open opportunities · showing the first 5"])
        XCTAssertFalse(app.staticTexts["Dropped: missing id"].exists)
        XCTAssertFalse(app.buttons["Apply"].exists)
    }

    func testChinesePlazaAndOfficialCopy() {
        launch(chinese: true)
        XCTAssertTrue(app.buttons["merchantCoopCenter.route.detail.70"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["合作中心"].exists)
        XCTAssertTrue(app.staticTexts["余 3 席"].exists)
        XCTAssertTrue(app.staticTexts["招商截止 10月10日"].exists)
        XCTAssertTrue(app.staticTexts["10月12日 – 10月14日"].exists)
        XCTAssertTrue(app.staticTexts["权益核销 · 权益不低于 ¥20"].exists)
        XCTAssertEqual(app.buttons["merchantCoopCenter.route.detail.70"].label, "看详情：Synthetic harbour walk")
        reveal(app.staticTexts["共 12 个开放商机 · 当前列出前 5 个"])
        tab("官方活动")
        XCTAssertTrue(app.buttons["merchantCoopCenter.event.81"].waitForExistence(timeout: 5))
        let gap = app.buttons["merchantCoopCenter.event.82"].label
        XCTAssertTrue(gap.contains("全城"), gap)
        XCTAssertTrue(gap.contains("信息不全"), gap)
        XCTAssertTrue(gap.contains("关键承接方缺失，待补位"), gap)
        XCTAssertTrue(gap.contains("查看活动"), gap)
        reveal(app.buttons["merchantCoopCenter.event.83"])
        XCTAssertFalse(app.buttons["merchantCoopCenter.event.84"].exists)
        XCTAssertFalse(app.buttons["merchantCoopCenter.event.85"].exists)
    }

    func testOfficialInitialTabGapAndReadOnlyDetail() {
        launch("official")
        let first = app.buttons["merchantCoopCenter.event.81"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls["merchantCoopCenter.tabs"].buttons["Official events"].isSelected)
        let fallback = app.buttons["merchantCoopCenter.event.82"].label
        XCTAssertTrue(fallback.contains("Citywide"), fallback)
        XCTAssertTrue(fallback.contains("A key partner is missing and a replacement is pending"), fallback)
        let reason = app.buttons["merchantCoopCenter.event.83"].label
        XCTAssertTrue(reason.contains("Synthetic: a key host is missing"), reason)
        XCTAssertFalse(reason.contains("A key partner is missing"), reason)
        first.tap()
        XCTAssertTrue(app.staticTexts["Synthetic city festival"].waitForExistence(timeout: 5))
    }

    func testFocusTopicIsHighlightedAndScrolledIntoView() {
        launch("focus")
        let focused = app.descendants(matching: .any)["merchantCoopCenter.route.74.focused"]
        XCTAssertTrue(focused.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["merchantCoopCenter.route.detail.74"].isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["merchantCoopCenter.route.70.focused"].exists)
    }

    func testDetailOpensChapterRecruitment() {
        launch()
        let detail = app.buttons["merchantCoopCenter.route.detail.70"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10)); detail.tap()
        XCTAssertTrue(app.navigationBars["Chapter recruitment"].waitForExistence(timeout: 5))
    }

    func testEmptyStatesOfferRefresh() {
        launch("empty")
        XCTAssertTrue(app.staticTexts["No open routes yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["merchantCoopCenter.refresh"].exists)
        XCTAssertFalse(app.staticTexts["merchantCoopCenter.plaza.scope"].exists)
        tab("Official events")
        XCTAssertTrue(app.staticTexts["No official events yet"].waitForExistence(timeout: 5))
        app.buttons["merchantCoopCenter.refresh"].tap()
        XCTAssertTrue(app.staticTexts["No official events yet"].waitForExistence(timeout: 5))
    }

    func testLoadFailureIsVisibleAndRetryRecovers() {
        launch("error")
        XCTAssertTrue(app.staticTexts["Routes did not load"].waitForExistence(timeout: 10))
        app.buttons["merchantCoopCenter.retry"].tap()
        XCTAssertTrue(app.buttons["merchantCoopCenter.route.detail.70"].waitForExistence(timeout: 5))
        tab("Official events")
        XCTAssertTrue(app.staticTexts["Official events did not load"].waitForExistence(timeout: 5))
        app.buttons["merchantCoopCenter.retry"].tap()
        XCTAssertTrue(app.buttons["merchantCoopCenter.event.81"].waitForExistence(timeout: 5))
    }

    func testPermissionDeniedAndSignedOutHaveNoRetry() {
        launch("denied")
        XCTAssertTrue(app.staticTexts["Not available right now"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["merchantCoopCenter.retry"].exists)
        tab("Official events")
        XCTAssertTrue(app.staticTexts["Not available right now"].waitForExistence(timeout: 5))
        app.terminate()
        launch("signedOut", chinese: true)
        XCTAssertTrue(app.staticTexts["登录后查看"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["请登录后查看经营信息"].exists)
    }

    func testBellOpensReceivedAndSentInbox() {
        launch()
        let bell = app.buttons["merchantCoopCenter.inbox"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        XCTAssertEqual(bell.label, "Cooperation invitations: received and sent")
        bell.tap()
        XCTAssertTrue(app.segmentedControls["cooperation.direction"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["merchantCoopCenter.route.detail.70"].waitForExistence(timeout: 5))
    }
}
