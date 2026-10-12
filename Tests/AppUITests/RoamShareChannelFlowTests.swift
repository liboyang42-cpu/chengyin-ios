import XCTest

/// These tests only render a synthetic local card and choose UI modes. They do not tap Photos,
/// album-guide actions or the system share sheet, and never publish or save an image.
final class RoamShareChannelFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", "content",
            "--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        runningApp = app; app.launch()
        let history = app.buttons["roam.experience.history.open"]
        XCTAssertTrue(revealFixtureElement(history, in: app)); history.tap()
        let record = app.buttons.matching(identifier: "roam.experience.history.record").firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        openShare(app); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func openShare(_ app: XCUIApplication) {
        let share = app.buttons["roam.share.open"]
        XCTAssertTrue(revealFixtureElement(share, in: app)); share.tap()
        XCTAssertTrue(element("roam.shareChannels.picker", app).waitForExistence(timeout: 5))
    }
    private func prepare(_ app: XCUIApplication) {
        let prepare = app.buttons["roam.share.prepare"]
        XCTAssertTrue(revealFixtureElement(prepare, in: app)); prepare.tap()
        XCTAssertTrue(app.buttons["roam.share.savePhotos"].waitForExistence(timeout: 5))
    }
    private func choose(_ raw: String, label: String, app: XCUIApplication) {
        let picker = element("roam.shareChannels.picker", app)
        XCTAssertTrue(revealFixtureElement(picker, in: app, towardTop: true)); picker.tap()
        let choice = app.buttons[label]
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        XCTAssertTrue(element("roam.shareChannels.selected." + raw, app).exists)
    }
    func testDefaultKeepsAllPreviouslySupportedActions() {
        let app = app(); prepare(app)
        for id in ["roam.albumGuide.open.moments", "roam.albumGuide.open.xiaohongshu", "roam.share.system"] {
            XCTAssertTrue(revealFixtureElement(app.buttons[id], in: app))
        }
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testSaveOnlyHidesAllSharingGuidanceAndSystemExport() {
        let app = app(); prepare(app); choose("saveOnly", label: "Save only", app: app)
        XCTAssertTrue(revealFixtureElement(app.buttons["roam.share.savePhotos"], in: app))
        XCTAssertFalse(app.buttons["roam.albumGuide.open.moments"].exists)
        XCTAssertFalse(app.buttons["roam.albumGuide.open.xiaohongshu"].exists)
        XCTAssertFalse(app.buttons["roam.share.system"].exists)
        XCTAssertFalse(app.buttons["roam.share.prepare"].exists)
    }
    func testMomentsModeKeepsOnlySaveAndMomentsGuide() {
        let app = app(); prepare(app); choose("momentsGuide", label: "Moments guide", app: app)
        XCTAssertTrue(revealFixtureElement(app.buttons["roam.albumGuide.open.moments"], in: app))
        XCTAssertTrue(app.buttons["roam.share.savePhotos"].exists)
        XCTAssertFalse(app.buttons["roam.albumGuide.open.xiaohongshu"].exists)
        XCTAssertFalse(app.buttons["roam.share.system"].exists)
    }
    func testRestoringAllOptionsKeepsSamePreparedCard() {
        let app = app(); prepare(app)
        choose("saveOnly", label: "Save only", app: app)
        choose("allOptions", label: "All sharing options", app: app)
        XCTAssertTrue(revealFixtureElement(app.buttons["roam.share.system"], in: app))
        XCTAssertFalse(app.buttons["roam.share.prepare"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testChoiceBeforeRenderingIsEnforcedAfterCardPreparation() {
        let app = app(); choose("saveOnly", label: "Save only", app: app); prepare(app)
        XCTAssertFalse(app.buttons["roam.share.system"].exists)
        XCTAssertFalse(app.buttons["roam.albumGuide.open.moments"].exists)
    }
    func testDismissAndReopenStartsNewEphemeralChoice() {
        let app = app(); choose("saveOnly", label: "Save only", app: app)
        let done = app.navigationBars.buttons["Done"]
        XCTAssertTrue(done.exists); done.tap(); openShare(app)
        XCTAssertTrue(element("roam.shareChannels.selected.allOptions", app).exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testChineseChoiceExplainsActionScopeWithoutFriendPrivacyPromise() {
        let app = app(chinese: true); choose("saveOnly", label: "仅保存", app: app)
        XCTAssertTrue(app.staticTexts["这里只选择可用操作，不会更改其他 App 的可见范围，也不会撤回已经分享的图片。"].exists)
        prepare(app); XCTAssertFalse(app.buttons["roam.share.system"].exists)
    }
}
