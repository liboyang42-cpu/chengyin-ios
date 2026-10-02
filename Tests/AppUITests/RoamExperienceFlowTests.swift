import XCTest

final class RoamExperienceFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func app(_ scenario: String = "content", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", scenario,
                               "--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    private func open(_ suffix: String, in app: XCUIApplication) {
        let link = app.buttons["roam.experience.\(suffix).open"]
        if !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
    }
    func testHistoryDistinguishesUnknownStatsAndShowsSession() {
        let app = app(); open("history", in: app)
        let record = app.buttons.matching(identifier: "roam.experience.history.record").firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "roam.experience.session").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved local journey"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Share"].exists)
    }
    func testCorruptHistoryIsErrorNotEmpty() {
        let app = app("historyCorrupt"); open("history", in: app)
        XCTAssertTrue(app.otherElements["roam.experience.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["roam.experience.history.empty"].exists)
        XCTAssertTrue(app.buttons["roam.experience.retry"].exists)
        XCTAssertTrue(app.staticTexts["Your roaming records could not be read. They have not been replaced."].exists)
    }
    func testEmptyHistoryIsNotAnError() {
        let app = app("empty"); open("history", in: app)
        XCTAssertTrue(app.otherElements["roam.experience.history.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["roam.experience.error"].exists)
        XCTAssertTrue(app.staticTexts["No local roaming records"].exists)
    }
    func testRecoveryNeedsIDAndOnlyDisplaysServerResultAfterRead() {
        let app = app(); open("recovery", in: app)
        let check = app.buttons["roam.experience.recovery.check"]
        XCTAssertFalse(check.isEnabled)
        let field = app.textFields["roam.experience.recovery.id"]
        field.tap(); field.typeText("901"); check.tap()
        XCTAssertTrue(app.staticTexts["Server settlement confirmed"].waitForExistence(timeout: 5))
    }
    func testIncompleteSettlementNeverShowsConfirmedRewards() {
        let app = app("incomplete"); open("recovery", in: app)
        let field = app.textFields["roam.experience.recovery.id"]
        field.tap(); field.typeText("901"); app.buttons["roam.experience.recovery.check"].tap()
        XCTAssertTrue(app.staticTexts["Settlement details are incomplete"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Server settlement confirmed"].exists)
    }
    func testAlbumHidesRejectedStampAndLabelsUnsubmittedReview() {
        let app = app(); open("album", in: app)
        XCTAssertTrue(app.staticTexts["Synthetic city stamp"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Hidden synthetic moderation fixture"].exists)
        XCTAssertTrue(app.staticTexts["Not submitted to automated review"].exists)
    }
    func testAlbumPageErrorKeepsAlreadyLoadedStamp() {
        let app = app("pageFailure"); open("album", in: app)
        app.swipeUp(); app.buttons["roam.experience.album.more"].tap()
        XCTAssertTrue(app.otherElements["roam.experience.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "roam.experience.album.stamp").count > 0)
    }
    func testLiveMemoryReadCannotStartGPSOrAwardXP() {
        let app = app(); open("live", in: app)
        app.buttons["roam.experience.tiles.load"].tap()
        XCTAssertTrue(app.staticTexts["All returned tile pages loaded"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertFalse(app.buttons["Start roaming"].exists)
    }
    func testCaptionDraftOnlyAndLengthValidation() {
        let app = app("captionDraft"); open("cityStamp", in: app)
        let field = app.textFields["roam.experience.stamp.caption"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(String(repeating: "a", count: 31))
        XCTAssertFalse(app.buttons["roam.experience.stamp.preview"].isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testDefaultCityStampEntryKeepsCameraDisabled() {
        let app = app(); open("cityStamp", in: app)
        let capture = app.buttons["media.stamp.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5)); XCTAssertFalse(capture.isEnabled)
        XCTAssertFalse(app.textFields["roam.experience.stamp.caption"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    func testSignOutRemovesPrivateAlbumAndChineseLoads() {
        let app = app("sessionChange", language: "zh-Hans"); open("album", in: app)
        XCTAssertTrue(app.staticTexts["Synthetic city stamp"].waitForExistence(timeout: 5))
        app.buttons["roam.experience.fixture.signOut"].tap()
        XCTAssertFalse(app.staticTexts["Synthetic city stamp"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "roam.experience.hub").firstMatch.waitForExistence(timeout: 5))
    }
}
