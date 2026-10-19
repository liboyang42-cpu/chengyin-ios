import XCTest

/// Offline 隐私与定位 and 我的待审媒体 (w2-03). Synthetic data only; nothing is written.
final class SettingsPrivacyLocationFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String, language: String = "en") {
        app.launchArguments = ["--uitesting-member-parity", "--member-parity-page", "privacy", "--member-parity-scenario", scenario,
                               "--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
    }
    private func openMedia() {
        let entry = app.buttons["member.privacy.media"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
    }
    func testPresenceOffIsVisibleButNeverSubmits() {
        launch("ready")
        let off = app.buttons["member.privacy.presence.off"]
        XCTAssertTrue(off.waitForExistence(timeout: 10))
        XCTAssertFalse(off.isEnabled)
        XCTAssertTrue(app.staticTexts["This build can't submit this change yet. Nothing has been changed."].exists)
    }
    func testMediaListPagesOlderRowsWithStates() {
        launch("ready"); openMedia()
        XCTAssertTrue(app.descendants(matching: .any)["member.media.row.200"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pending review"].exists)
        let older = app.buttons["member.media.older"]
        for _ in 0..<12 where !older.exists { app.swipeUp() }
        XCTAssertTrue(older.waitForExistence(timeout: 5)); older.tap()
        let oldest = app.descendants(matching: .any)["member.media.row.11"]
        for _ in 0..<4 where !oldest.exists { app.swipeUp() }
        XCTAssertTrue(oldest.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["member.media.older"].exists)
    }
    func testFailureRetriesAndDormantExplainsInChinese() {
        launch("failure"); openMedia()
        let retry = app.buttons["member.media.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(app.buttons["member.media.refresh"].waitForExistence(timeout: 5))
        app.terminate()
        launch("dormant", language: "zh-Hans"); openMedia()
        XCTAssertTrue(app.staticTexts["当前配置暂不能读取本人媒体。"].waitForExistence(timeout: 5))
    }
    func testEmptyAndDeniedStatesUseSourceCopy() {
        launch("empty"); openMedia()
        XCTAssertTrue(app.staticTexts["No uploaded media yet"].waitForExistence(timeout: 5))
        app.terminate()
        launch("denied"); openMedia()
        XCTAssertTrue(app.staticTexts["This account can't read its media right now. Refresh and try again."].waitForExistence(timeout: 5))
    }
}
