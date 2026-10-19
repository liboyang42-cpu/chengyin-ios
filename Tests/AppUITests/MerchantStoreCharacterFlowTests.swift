import XCTest

/// Synthetic offline fixture only: `--uitesting-module merchant-city-npc --w2-19-page aiNPC`.
final class MerchantStoreCharacterFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String, chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US",
                               "--uitesting-module", "merchant-city-npc", "--w2-19-page", "aiNPC", "--w2-19-scenario", scenario]
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
    }
    private func tapSwitch(_ id: String) {
        let toggle = app.switches[id].firstMatch
        reveal(toggle)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }
    private func editName(_ text: String) {
        app.buttons["aiNPC.row.name"].tap()
        let input = app.textFields["aiNPC.field.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(text)
        app.buttons["aiNPC.field.save"].tap()
    }

    func testHomeShowsSourceRowsBadgeAndNoReformSection() {
        launch("normal")
        XCTAssertTrue(app.navigationBars["AI Store Character"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sample Lantern Host"].exists)
        XCTAssertTrue(app.staticTexts["Live"].exists)
        for id in ["avatar", "voice", "name", "greeting", "persona", "knowledge", "mapPoint"] { reveal(app.buttons["aiNPC.row." + id]) }
        XCTAssertTrue(app.staticTexts["Voice ready"].exists)
        XCTAssertTrue(app.staticTexts["Sample address, Example District"].exists)
        XCTAssertFalse(app.staticTexts["Scene scopes (not enabled)"].exists)
    }
    func testChineseRejectedBadgeAndReason() {
        launch("rejected", chinese: true)
        XCTAssertTrue(app.navigationBars["AI 店铺角色"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["已驳回"].exists)
        let reason = app.staticTexts["aiNPC.hero.rejectReason"]
        XCTAssertTrue(reason.exists); XCTAssertTrue(reason.label.hasPrefix("驳回理由："))
        XCTAssertTrue(app.staticTexts["尚未选择地图位置"].exists)
    }
    func testChineseEmptyProfileBlocksVoiceUntilSaved() {
        launch("empty", chinese: true)
        XCTAssertTrue(app.staticTexts["给角色起个名字"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["审核中"].exists)
        app.buttons["aiNPC.row.voice"].tap()
        XCTAssertTrue(app.staticTexts["请先保存角色形象"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["填写菜单、招牌与营业信息"].exists)
    }
    func testDeniedRoleUsesSourceCopy() {
        launch("denied")
        XCTAssertTrue(app.staticTexts["Your store role does not have this permission."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["aiNPC.row.name"].exists)
    }
    func testLoadFailureOffersRetry() {
        launch("error")
        XCTAssertTrue(app.staticTexts["Character details could not be opened"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["aiNPC.retry"].exists)
    }
    func testDefaultGatesKeepSavesLocal() {
        launch("normal")
        XCTAssertTrue(app.buttons["aiNPC.row.name"].waitForExistence(timeout: 10))
        editName(" more")
        XCTAssertTrue(app.staticTexts["Saving is not available yet. Changes on this page are not submitted."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["aiNPC.save.confirm"].exists)
    }
    func testFirstSaveNeedsConfirmationThenShowsReviewing() {
        launch("saveSuccess")
        XCTAssertTrue(app.buttons["aiNPC.row.name"].waitForExistence(timeout: 10))
        editName("Sample Host")
        let confirm = app.buttons["aiNPC.save.confirm"]
        reveal(confirm); confirm.tap()
        XCTAssertTrue(app.staticTexts["Character updated"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["In review"].exists)
    }
    func testRejectedSaveShowsServerMessage() {
        launch("saveRejected")
        XCTAssertTrue(app.buttons["aiNPC.row.name"].waitForExistence(timeout: 10))
        editName("Sample Host")
        let confirm = app.buttons["aiNPC.save.confirm"]
        reveal(confirm); confirm.tap()
        XCTAssertTrue(app.staticTexts["Sample content check rejected this text."].waitForExistence(timeout: 5))
    }
    func testUncertainSaveReadsBackInsteadOfResending() {
        launch("saveUnknown")
        XCTAssertTrue(app.buttons["aiNPC.row.name"].waitForExistence(timeout: 10))
        editName("Sample Host")
        let confirm = app.buttons["aiNPC.save.confirm"]
        reveal(confirm); confirm.tap()
        XCTAssertTrue(app.staticTexts["Save confirmed. The latest character details were read from the server."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample Host"].exists)
    }
    func testPresetSelectionThenDiscardSheet() {
        launch("normal")
        XCTAssertTrue(app.buttons["aiNPC.row.avatar"].waitForExistence(timeout: 10)); app.buttons["aiNPC.row.avatar"].tap()
        XCTAssertTrue(app.navigationBars["Upload Character Look"].waitForExistence(timeout: 5))
        app.buttons["aiNPC.avatar.presets"].tap()
        XCTAssertTrue(app.buttons["aiNPC.preset.p23"].waitForExistence(timeout: 5)); app.buttons["aiNPC.preset.p23"].tap()
        app.buttons["aiNPC.preset.use"].tap()
        app.buttons["aiNPC.back"].tap()
        XCTAssertTrue(app.staticTexts["Not saved yet"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.navigationBars["AI Store Character"].waitForExistence(timeout: 5))
    }
    func testPhotoUploadIsMarkedUnavailable() {
        launch("normal", chinese: true)
        XCTAssertTrue(app.buttons["aiNPC.row.avatar"].waitForExistence(timeout: 10)); app.buttons["aiNPC.row.avatar"].tap()
        app.buttons["aiNPC.avatar.photo"].tap()
        XCTAssertTrue(app.staticTexts["照片形象需在端上裁剪并处理成像素画，此版本暂未开放。"].waitForExistence(timeout: 5))
    }
    func testVoiceEnrollRecordsSeparateConsentFirst() {
        launch("voiceEnroll")
        XCTAssertTrue(app.buttons["aiNPC.row.voice"].waitForExistence(timeout: 10)); app.buttons["aiNPC.row.voice"].tap()
        XCTAssertTrue(app.navigationBars["Record character voice"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["aiNPC.voice.hold"].isEnabled)
        tapSwitch("aiNPC.voice.consent")
        let sample = app.buttons["aiNPC.voice.useSample"]; reveal(sample); sample.tap()
        XCTAssertTrue(app.staticTexts["All three sentences recorded"].waitForExistence(timeout: 5))
        let enroll = app.buttons["aiNPC.voice.enroll"]; reveal(enroll); enroll.tap()
        let agree = app.buttons["aiNPC.consent.agree"]; reveal(agree)
        XCTAssertTrue(app.staticTexts["Voice cloning processing"].exists)
        agree.tap()
        XCTAssertTrue(app.navigationBars["Voice is being created"].waitForExistence(timeout: 5))
    }
    func testVoiceConsentDeclineStopsOnlyThisFeature() {
        launch("voiceEnroll", chinese: true)
        XCTAssertTrue(app.buttons["aiNPC.row.voice"].waitForExistence(timeout: 10)); app.buttons["aiNPC.row.voice"].tap()
        tapSwitch("aiNPC.voice.consent")
        let sample = app.buttons["aiNPC.voice.useSample"]; reveal(sample); sample.tap()
        let enroll = app.buttons["aiNPC.voice.enroll"]; reveal(enroll); enroll.tap()
        let decline = app.buttons["aiNPC.consent.decline"]; reveal(decline); decline.tap()
        XCTAssertTrue(app.staticTexts["已拒绝，仅停止此功能"].waitForExistence(timeout: 5))
    }
    func testUncertainEnrollChecksStatus() {
        launch("voiceUnknown")
        XCTAssertTrue(app.buttons["aiNPC.row.voice"].waitForExistence(timeout: 10)); app.buttons["aiNPC.row.voice"].tap()
        tapSwitch("aiNPC.voice.consent")
        let sample = app.buttons["aiNPC.voice.useSample"]; reveal(sample); sample.tap()
        let enroll = app.buttons["aiNPC.voice.enroll"]; reveal(enroll); enroll.tap()
        let agree = app.buttons["aiNPC.consent.agree"]; reveal(agree); agree.tap()
        XCTAssertTrue(app.staticTexts["The voice creation result is not confirmed. Check the creation status first."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Voice is being created"].waitForExistence(timeout: 5))
    }
    func testPendingVoicePollsUntilReady() {
        launch("voicePending")
        XCTAssertTrue(app.staticTexts["Voice is being created"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Voice ready"].waitForExistence(timeout: 20))
    }
    func testMapPointConfirmThenReadback() {
        launch("mapPoint")
        let row = app.buttons["aiNPC.row.mapPoint"]
        reveal(row)
        XCTAssertTrue(app.staticTexts["No map location selected yet"].exists)
        row.tap()
        XCTAssertTrue(app.staticTexts["Save roaming map point?"].waitForExistence(timeout: 5))
        app.buttons["Confirm and save"].tap()
        XCTAssertTrue(app.staticTexts["Sample picked point, Example District"].waitForExistence(timeout: 5))
    }
    func testReformScopesOnlyWithFixtureGates() {
        launch("scopes", chinese: true)
        let header = app.staticTexts["场景范围（未启用）"]
        reveal(header)
        reveal(app.staticTexts["aiNPC.reform.knowledge"])
        reveal(app.staticTexts["aiNPC.reform.blocker.capabilityDisabled"])
    }
}
