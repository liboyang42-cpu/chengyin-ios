import XCTest

/// FE-STORY visit gate with synthetic fixtures only (neutral 「示例站点」 places).
final class FreeExplorationStoryFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ scenario: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playExperience", "--uitesting-play-experience-scenario", scenario,
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        runningApp = app; app.launch(); return app
    }
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func text(_ value: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch
    }
    private func openLockedPlace(_ app: XCUIApplication) {
        let pack = app.buttons["playFree.pack.open"]
        XCTAssertTrue(pack.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(pack, in: app), app.debugDescription); pack.tap()
        let store = app.buttons["playFree.store.701"]
        XCTAssertTrue(revealFixtureElement(store, in: app), app.debugDescription); store.tap()
        XCTAssertTrue(app.navigationBars["Store visit"].waitForExistence(timeout: 5), app.debugDescription)
    }
    private func tapArrive(_ app: XCUIApplication) {
        let action = app.buttons["playArrival.action.701"]
        XCTAssertTrue(revealFixtureElement(action, in: app), app.debugDescription)
        XCTAssertTrue(action.isEnabled, app.debugDescription); action.tap()
    }

    func testLockedCardHidesStoryAndReadsVisitRuleToVoiceOver() {
        let app = launch("feStory"); openLockedPlace(app)
        let badge = element("playFree.story.locked.701", in: app)
        XCTAssertTrue(revealFixtureElement(badge, in: app), app.debugDescription)
        XCTAssertEqual(badge.label, "Locked. Readable after you visit")
        XCTAssertTrue(text("Synthetic hook line", in: app).exists, app.debugDescription)
        XCTAssertFalse(text("Synthetic stale locked description", in: app).exists)
        XCTAssertFalse(text("Synthetic stale locked story", in: app).exists)
        XCTAssertFalse(app.buttons["Read this store’s story"].exists)
        attachFixtureScreenshot(self, app: app, name: "Locked free-exploration card shows no chapter text")
    }

    func testChineseLockedCardVoiceOverLabel() {
        let app = launch("feStory", language: "zh-Hans")
        let pack = app.buttons["playFree.pack.open"]; XCTAssertTrue(pack.waitForExistence(timeout: 10)); XCTAssertTrue(revealFixtureElement(pack, in: app)); pack.tap()
        let store = app.buttons["playFree.store.701"]; XCTAssertTrue(revealFixtureElement(store, in: app)); store.tap()
        let badge = element("playFree.story.locked.701", in: app)
        XCTAssertTrue(revealFixtureElement(badge, in: app), app.debugDescription)
        XCTAssertEqual(badge.label, "未解锁，到访后可读")
    }

    func testArrivalSuccessUnlocksChapterText() {
        let app = launch("feStory"); openLockedPlace(app); tapArrive(app)
        let unlocked = text("Synthetic unlocked chapter text", in: app)
        XCTAssertTrue(unlocked.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("playFree.story.locked.701", in: app).exists)
        attachFixtureScreenshot(self, app: app, name: "Visit confirmed and chapter unlocked")
    }

    func testArrivalTooFarShowsDistanceAndKeepsChapterLocked() {
        let app = launch("feStoryTooFar"); openLockedPlace(app); tapArrive(app)
        let rejected = element("playArrival.rejected", in: app)
        XCTAssertTrue(rejected.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(rejected.label.contains("340"), rejected.label)
        XCTAssertTrue(element("playFree.story.locked.701", in: app).exists)
        XCTAssertFalse(text("Synthetic unlocked chapter text", in: app).exists)
        XCTAssertTrue(app.buttons["playArrival.action.701"].isEnabled)
        attachFixtureScreenshot(self, app: app, name: "Too far shows the distance")
    }

    func testArrivalUnknownRereadsWithoutResend() {
        let app = launch("feStoryUnknown"); openLockedPlace(app); tapArrive(app)
        let unknown = element("playArrival.unknown", in: app)
        XCTAssertTrue(unknown.waitForExistence(timeout: 10), app.debugDescription)
        let action = app.buttons["playArrival.action.701"]
        XCTAssertFalse(action.exists && action.isEnabled, "An unknown visit must not be sent again")
        let reread = app.buttons["playArrival.reread"]
        XCTAssertTrue(revealFixtureElement(reread, in: app), app.debugDescription); reread.tap()
        XCTAssertTrue(unknown.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(action.exists && action.isEnabled)
        XCTAssertFalse(text("Synthetic unlocked chapter text", in: app).exists)
        attachFixtureScreenshot(self, app: app, name: "Unknown visit is re-read, not re-sent")
    }

    func testTeammateVisitIsLabelled() {
        let app = launch("feStory")
        let pack = app.buttons["playFree.pack.open"]; XCTAssertTrue(pack.waitForExistence(timeout: 10)); XCTAssertTrue(revealFixtureElement(pack, in: app)); pack.tap()
        let store = app.buttons["playFree.store.702"]; XCTAssertTrue(revealFixtureElement(store, in: app)); store.tap()
        let team = element("playFree.story.team.702", in: app)
        XCTAssertTrue(revealFixtureElement(team, in: app), app.debugDescription)
        XCTAssertTrue(team.label.contains("A teammate visited"), team.label)
        XCTAssertTrue(text("Synthetic team unlocked text", in: app).exists)
    }

    func testOfflineShowsCachedUnlockedChaptersReadOnly() {
        let app = launch("feOffline")
        XCTAssertTrue(app.buttons["playFree.pack.open"].waitForExistence(timeout: 10), app.debugDescription)
        let refresh = app.buttons["playFree.refresh"]; XCTAssertTrue(revealFixtureElement(refresh, in: app)); refresh.tap()
        let notice = element("playFree.archive.notice", in: app)
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("Synthetic team unlocked text", in: app).exists, app.debugDescription)
        let locked = element("playFree.archive.locked.701", in: app)
        XCTAssertTrue(revealFixtureElement(locked, in: app), app.debugDescription)
        XCTAssertTrue(locked.label.contains("Unlocks only when you are back online"), locked.label)
        XCTAssertFalse(text("Synthetic stale locked description", in: app).exists)
        XCTAssertFalse(app.buttons["playArrival.action.701"].exists)
        attachFixtureScreenshot(self, app: app, name: "Offline cached chapters are read-only")
    }

    func testExpiredTicketShowsVisitedChaptersOnly() {
        let app = launch("feExpired", language: "zh-Hans")
        let notice = element("playFree.archive.notice", in: app)
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("Synthetic expired chapter block", in: app).exists, app.debugDescription)
        let locked = element("playFree.archive.locked.701", in: app)
        XCTAssertTrue(revealFixtureElement(locked, in: app), app.debugDescription)
        XCTAssertTrue(locked.label.contains("已过期，不能再解锁"), locked.label)
        XCTAssertFalse(app.buttons["playArrival.action.701"].exists)
        XCTAssertFalse(app.buttons["playFree.pack.open"].exists)
        attachFixtureScreenshot(self, app: app, name: "Expired ticket keeps visited chapters readable")
    }
}
