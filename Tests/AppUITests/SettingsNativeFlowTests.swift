import XCTest

/// Requires ModuleFixture.settingsNative -> SettingsFixtureHostView. Offline, memory-backed.
/// Authored in Linux; simulator/runtime evidence remains NOT_RUN until the Apple-toolchain run.
final class SettingsNativeFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", market: String = "CN", language: String = "en", extra: [String] = []) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-market", market, "--uitesting-module", "settingsNative", "--uitesting-settings-scenario", scenario] + extra
        app.launch()
    }
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<10 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
    private func open(_ id: String) { let button = app.buttons[id]; reveal(button); button.tap() }
    private func back() { app.navigationBars.buttons.firstMatch.tap() }
    private func expectSwitch(_ element: XCUIElement, value: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, app.debugDescription)
    }
    private func tapNativeSwitch(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        tapFixtureNativeSwitch(element, in: app, file: file, line: line)
    }

    func testSoundSixDefaultsSaveBackAndReopen() {
        launch(); open("settingsNative.openSound")
        let sound = app.switches["settingsNative.sound.sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5)); expectSwitch(sound, value: "1")
        for key in ["haptics", "airplane"] { expectSwitch(app.switches["settingsNative.sound.\(key)"], value: "1") }
        for key in ["ocean", "raindrop", "forest"] { expectSwitch(app.switches["settingsNative.sound.\(key)"], value: "0") }
        tapNativeSwitch(sound); expectSwitch(sound, value: "0")
        back(); open("settingsNative.openSound")
        XCTAssertTrue(sound.waitForExistence(timeout: 5)); expectSwitch(sound, value: "0")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func testSoundLoadFailureAndRetry() {
        launch("loadFailure"); open("settingsNative.openSound")
        XCTAssertTrue(app.staticTexts["settingsNative.sound.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["settingsNative.sound.sound"].exists)
        open("settingsNative.sound.retry")
        XCTAssertTrue(app.switches["settingsNative.sound.sound"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settingsNative.sound.error"].exists)
    }
    func testFailedSaveKeepsPreviousValueAndNextTapCanSave() {
        launch("saveFailure"); open("settingsNative.openSound")
        let sound = app.switches["settingsNative.sound.sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5)); tapNativeSwitch(sound)
        // A failed save appends its message below the local-only disclosure.
        reveal(app.staticTexts["settingsNative.sound.error"])
        expectSwitch(sound, value: "1")
        tapNativeSwitch(sound); expectSwitch(sound, value: "0")
        XCTAssertFalse(app.staticTexts["settingsNative.sound.error"].exists)
    }
    func testCNEnglishInterfacePreservesChineseSourceAndVersion() {
        launch(language: "en"); open("settingsNative.openLegal.user_agreement")
        XCTAssertTrue(app.staticTexts["settingsNative.legal.sourceNotice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["用户服务协议"].exists)
        XCTAssertEqual(app.staticTexts["settingsNative.legal.version"].label, "v2.2")
        XCTAssertFalse(app.buttons["Accept"].exists); XCTAssertFalse(app.buttons["Agree"].exists)
        attachFixtureScreenshot(self, app: app, name: "CN legal source with English interface and provenance")
        back(); open("settingsNative.openLegal.privacy_policy")
        XCTAssertTrue(app.staticTexts["settingsNative.legal.missing"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settingsNative.legal.version"].exists)
    }
    func testUSChineseLanguageNeverDisplaysCNAgreement() {
        launch(market: "US", language: "zh-Hans"); open("settingsNative.openLegal.user_agreement")
        XCTAssertTrue(app.staticTexts["settingsNative.legal.missing"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settingsNative.legal.sourceNotice"].exists)
        XCTAssertFalse(app.staticTexts["settingsNative.legal.version"].exists)
        back(); open("settingsNative.openAbout")
        let market = app.descendants(matching: .any)["settingsNative.about.market"].firstMatch
        XCTAssertTrue(market.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(market.label, "运营地区")
        XCTAssertEqual(market.value as? String, "US")
        XCTAssertFalse(app.staticTexts["settingsNative.about.contactPhone"].exists)
    }
    func testMissingMarketShowsNoRegionalLegalContent() {
        launch("missingMarket"); open("settingsNative.openLegal.user_agreement")
        XCTAssertTrue(app.staticTexts["settingsNative.legal.missing"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settingsNative.legal.version"].exists)
    }
    func testLegalFailureRetryAndBackReopen() {
        launch("legalFailure"); open("settingsNative.openLegal.user_agreement")
        XCTAssertTrue(app.staticTexts["settingsNative.legal.error"].waitForExistence(timeout: 5))
        open("settingsNative.legal.retry")
        XCTAssertTrue(app.staticTexts["settingsNative.legal.sourceNotice"].waitForExistence(timeout: 5))
        back(); open("settingsNative.openLegal.cancellation_notice")
        XCTAssertTrue(app.staticTexts["settingsNative.legal.version"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["settingsNative.legal.version"].label, "v2.1")
    }
    func testAboutReadsNativeBundleAndDoesNotInventCode() {
        launch(); open("settingsNative.openAbout")
        XCTAssertTrue(app.staticTexts["settingsNative.about.appName"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["settingsNative.about.appName"].label, "Questify")
        XCTAssertTrue(app.staticTexts["settingsNative.about.version"].exists)
        XCTAssertFalse(app.staticTexts["settingsNative.about.version"].label.isEmpty)
        reveal(app.staticTexts["settingsNative.about.codeUnavailable"])
        XCTAssertFalse(app.images["player-code-image"].exists)
        XCTAssertFalse(app.buttons["Call"].exists)
        open("settingsNative.about.openLegal.privacy_policy")
        XCTAssertTrue(app.staticTexts["settingsNative.legal.missing"].waitForExistence(timeout: 5))
        back(); XCTAssertTrue(app.navigationBars["About"].exists)
    }
    func testMissingMetadataIsNotReplacedByFakeVersion() {
        launch("missingMetadata"); open("settingsNative.openAbout")
        XCTAssertTrue(app.staticTexts["App name unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settingsNative.about.version"].exists)
        XCTAssertFalse(app.staticTexts["settingsNative.about.build"].exists)
    }
    func testPrivacyMarketingAndDeletionDoNotPresentActionSwitches() {
        for feature in ["locationConsent", "marketingConsent", "accountDeletion"] {
            launch(); open("settingsNative.openBlocked.\(feature)")
            XCTAssertTrue(app.staticTexts["settingsNative.blocked.message"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.switches.count, 0)
            XCTAssertFalse(app.buttons["Delete account"].exists)
            open("settingsNative.blocked.openDocument")
            if feature == "accountDeletion" {
                XCTAssertTrue(app.staticTexts["settingsNative.legal.version"].waitForExistence(timeout: 5))
            } else { XCTAssertTrue(app.staticTexts["settingsNative.legal.missing"].waitForExistence(timeout: 5)) }
            app.terminate()
        }
    }
    func testLargeTextChineseSoundControlsStayNativeAndAccessible() {
        launch(language: "zh-Hans", extra: ["--uitesting-max-text"])
        assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility5")
        open("settingsNative.openSound")
        let forest = app.switches["settingsNative.sound.forest"]
        reveal(forest); XCTAssertEqual(forest.label, "森林")
        tapNativeSwitch(forest); expectSwitch(forest, value: "1")
        attachFixtureScreenshot(self, app: app, name: "Chinese sound preferences at maximum accessibility text size")
    }
    func testContactCopyFeedbackClearsOnBackAndReopenWithoutCalling() {
        launch(); open("settingsNative.openAbout"); open("settingsNative.about.copyPhone")
        XCTAssertTrue(app.staticTexts["settingsNative.about.copyPhone.copied"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Call"].exists)
        attachFixtureScreenshot(self, app: app, name: "Settings contact explicit local copy feedback")
        back(); open("settingsNative.openAbout")
        reveal(app.buttons["settingsNative.about.copyPhone"])
        XCTAssertFalse(app.staticTexts["settingsNative.about.copyPhone.copied"].exists)
    }
    func testChineseLargeTextContactCopyFailureOffersManualRecovery() {
        launch("copyFailure", language: "zh-Hans", extra: ["--uitesting-large-text", "--uitesting-dark"])
        assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility3")
        open("settingsNative.openAbout"); open("settingsNative.about.copyPhone")
        let failure = app.staticTexts["settingsNative.about.copyPhone.failed"]
        reveal(failure)
        XCTAssertEqual(failure.label, "复制失败，请选择文字后手动复制。")
        XCTAssertFalse(app.staticTexts["settingsNative.about.copyPhone.copied"].exists)
        XCTAssertTrue(app.staticTexts["settingsNative.about.contactPhone"].exists)
        attachFixtureScreenshot(self, app: app, name: "Settings local copy failure Chinese large text dark mode")
    }

    func testAttributionCopiesEachExactSourceAddressWithSeparateFeedback() {
        launch()
        let gameCopy = "settingsNative.attribution.copy.game-icons"
        let artCopy = "settingsNative.attribution.copy.ansimuz"
        open(gameCopy)
        XCTAssertTrue(app.staticTexts[gameCopy + ".copied"].waitForExistence(timeout: 5))
        let receipt = app.staticTexts["settingsNative.fixture.copiedText"]
        reveal(receipt)
        XCTAssertEqual(receipt.label, "https://game-icons.net/")
        XCTAssertFalse(app.staticTexts[artCopy + ".copied"].exists)
        open(artCopy)
        XCTAssertTrue(app.staticTexts[artCopy + ".copied"].waitForExistence(timeout: 5))
        reveal(receipt)
        XCTAssertEqual(receipt.label, "https://ansimuz.itch.io/")
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testAttributionCopyFailureKeepsSourceVisibleAndExplicitRetrySucceeds() {
        launch("attributionCopyFailure")
        let copy = "settingsNative.attribution.copy.ansimuz"
        open(copy)
        XCTAssertTrue(app.staticTexts[copy + ".failed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[copy + ".copied"].exists)
        XCTAssertFalse(app.staticTexts["settingsNative.fixture.copiedText"].exists)
        XCTAssertTrue(app.staticTexts["https://ansimuz.itch.io/"].exists)
        open(copy)
        XCTAssertTrue(app.staticTexts[copy + ".copied"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[copy + ".failed"].exists)
        let receipt = app.staticTexts["settingsNative.fixture.copiedText"]
        reveal(receipt)
        XCTAssertEqual(receipt.label, "https://ansimuz.itch.io/")
    }

    func testChineseMaximumTextAttributionCopyResetsAfterAboutNavigation() {
        launch(language: "zh-Hans", extra: ["--uitesting-max-text", "--uitesting-dark"])
        assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility5")
        let copy = "settingsNative.attribution.copy.game-icons"
        let button = app.buttons[copy]
        reveal(button)
        XCTAssertEqual(button.label, "复制 game-icons.net 来源地址")
        button.tap()
        let feedback = app.staticTexts[copy + ".copied"]
        reveal(feedback)
        XCTAssertEqual(feedback.label, "已复制到剪贴板。")
        let about = app.buttons["settingsNative.openAbout"]
        for _ in 0..<12 { if about.exists && about.isHittable { break }; app.swipeDown() }
        open("settingsNative.openAbout")
        XCTAssertTrue(app.staticTexts["settingsNative.about.appName"].waitForExistence(timeout: 5))
        back()
        reveal(button)
        XCTAssertFalse(feedback.exists)
        button.tap()
        reveal(feedback)
        XCTAssertEqual(feedback.label, "已复制到剪贴板。")
        attachFixtureScreenshot(self, app: app, name: "Chinese attribution local copy at maximum text size")
    }

}
