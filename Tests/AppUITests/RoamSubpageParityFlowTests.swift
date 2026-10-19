import XCTest

/// subpackageRoam parity in the DEBUG-only `--roam-subpage-fixture` host. Synthetic data only;
/// no session, network, location, camera or write.
final class RoamSubpageParityFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func launch(_ scenario: String, language: String = "zh-Hans") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--roam-subpage-fixture", scenario, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testHistoryShowsStripToolsAndRunCards() {
        let app = launch("history")
        XCTAssertTrue(element("roamSub.w208.history.strip", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("roamSub.w208.history.strip", app).label.contains("次漫游"))
        XCTAssertTrue(element("roamSub.w208.history.tool.anniversary", app).exists)
        XCTAssertTrue(element("roamSub.w208.history.tool.recap", app).exists)
        XCTAssertTrue(revealFixtureElement(element("roamSub.w208.history.runCard", app), in: app, requiresHittable: false))
        element("roamSub.w208.history.tool.export", app).tap()
        XCTAssertTrue(element("roamSub.w208.history.exportUnavailable", app).waitForExistence(timeout: 5))
    }

    func testSharedFootprintReadyGoneErrorAndUnavailable() {
        var app = launch("sharedReady", language: "en")
        XCTAssertTrue(element("roamSub.w208.shared.card", app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("roamSub.w208.shared.routeName", app).label, "Demo lane footprints")
        app.terminate()
        app = launch("sharedGone")
        XCTAssertTrue(element("roamSub.w208.shared.gone", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["这条足迹已不再公开"].exists)
        app.terminate()
        app = launch("sharedError")
        XCTAssertTrue(element("roamSub.w208.shared.error", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["roamSub.w208.shared.retry"].exists)
        app.terminate()
        app = launch("sharedUnavailable")
        XCTAssertTrue(element("roamSub.w208.shared.unavailable", app).waitForExistence(timeout: 5))
    }

    func testPOINodeCardOfflineVoucherAndDormantInteraction() {
        var app = launch("poiOffline")
        XCTAssertTrue(element("roamSub.w208.poi.node", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["漫游 · 到店互动"].exists)
        XCTAssertTrue(element("roamSub.w208.poi.offline", app).label.contains("仍可出码领取"))
        XCTAssertTrue(element("roamSub.w208.poi.method", app).label.contains("完成领券"))
        XCTAssertEqual(app.buttons["roamSub.w208.poi.primary"].label, "出示核销码")
        app.buttons["roamSub.w208.poi.primary"].tap()
        XCTAssertTrue(element("roamSub.w208.voucher.disabled", app).waitForExistence(timeout: 5), "No approved factory: no code request")
        app.terminate()
        app = launch("poiLive")
        XCTAssertTrue(app.buttons["roamSub.w208.poi.primary"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["roamSub.w208.poi.primary"].label, "开始互动")
        XCTAssertFalse(app.buttons["roamSub.w208.poi.primary"].isEnabled)
    }

    func testPOIUnavailableAndMissingHaveNoRetry() {
        var app = launch("poiUnavailable")
        XCTAssertTrue(element("roamSub.w208.poi.unavailable", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["据点未开放或已下线"].exists)
        XCTAssertTrue(app.buttons["返回地图"].exists)
        app.terminate()
        app = launch("poiMissing")
        XCTAssertTrue(app.staticTexts["找不到这个据点"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["重试"].exists)
    }

    func testVoucherMissingParameterOffersOnlyBack() {
        let app = launch("voucherMissing")
        XCTAssertTrue(app.staticTexts["这个核销码打不开"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["roamSub.w208.voucher.back"].exists)
        XCTAssertFalse(app.buttons["verificationCode.show"].exists)
    }

    func testStampSlipRequiresRevealBeforeTakingIt() {
        var app = launch("stampExchanged")
        XCTAssertTrue(app.staticTexts["城市贴纸"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["roamSub.w208.stamp.send"].tap()
        XCTAssertTrue(element("roamSub.w208.stamp.slip", app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("roamSub.w208.stamp.serial", app).label, "NO. 2345")
        XCTAssertFalse(app.buttons["roamSub.w208.stamp.done"].isEnabled)
        let paper = element("roamSub.w208.stamp.slip", app)
        paper.press(forDuration: 0.1, thenDragTo: paper.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.6)))
        if app.buttons["roamSub.w208.stamp.tear"].exists { app.buttons["roamSub.w208.stamp.tear"].tap() }
        XCTAssertTrue(app.buttons["roamSub.w208.stamp.scratch"].waitForExistence(timeout: 5))
        app.buttons["roamSub.w208.stamp.scratch"].tap()
        XCTAssertTrue(app.buttons["roamSub.w208.stamp.done"].isEnabled)
        app.terminate()
        app = launch("stampNoExchange")
        app.buttons["roamSub.w208.stamp.send"].tap()
        XCTAssertTrue(element("roamSub.w208.stamp.noExchange", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["还没有可以换的票"].exists)
        XCTAssertTrue(app.buttons["roamSub.w208.stamp.done"].isEnabled)
    }

    func testStampWriteStepIsDormantWithoutExchange() {
        let app = launch("stampDormant")
        XCTAssertTrue(app.staticTexts["今日城市签"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(element("roamSub.w208.stamp.dormant", app).exists)
        XCTAssertFalse(app.buttons["roamSub.w208.stamp.send"].isEnabled)
        XCTAssertEqual(element("roamSub.w208.stamp.counter", app).label, "0/30")
    }
}
