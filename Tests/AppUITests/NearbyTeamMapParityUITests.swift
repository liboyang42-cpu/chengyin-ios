import XCTest

/// Nearby map/list and my-teams 附近在招募 parity in the DEBUG-only `--nearby-team-fixture` host.
/// Synthetic rows and a fixed manual point; no location prompt, live session or write.
final class NearbyTeamMapParityUITests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func launch(language: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--nearby-team-fixture"] + extra + ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testHeaderCountListToggleAndBadges() {
        let app = launch(language: "zh-Hans")
        let header = element("nearby.w208.header", app)
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(header.label.contains("附近的队伍 · 6 支在招募"), header.label)
        XCTAssertTrue(element("nearby.w208.map", app).exists)
        XCTAssertEqual(app.alerts.count, 0, "No location permission prompt")
        app.segmentedControls["nearby.w208.viewMode"].buttons["列表"].tap()
        let listHeader = element("nearby.w208.listHeader", app)
        XCTAssertTrue(revealFixtureElement(listHeader, in: app, requiresHittable: false))
        XCTAssertTrue(listHeader.label.contains("支"), listHeader.label)
        let row = app.buttons["nearby.w208.row.504"]
        XCTAssertTrue(revealFixtureElement(row, in: app))
        XCTAssertTrue(row.label.contains("需购票"), row.label)
        row.tap()
        XCTAssertTrue(revealFixtureElement(element("nearby.team.504", app), in: app, requiresHittable: false))
        XCTAssertTrue(app.staticTexts["加入队伍需要先持有这一场的票"].exists)
    }

    func testEmptyMineFallsThroughToRecruitingNearby() {
        let app = launch(language: "zh-Hans", extra: ["--nearby-team-fixture-empty-mine"])
        let empty = element("nearby.mine.empty", app)
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertEqual(empty.label, "还没有队伍")
        let title = element("nearby.w208.recruit.title", app)
        XCTAssertTrue(revealFixtureElement(title, in: app, requiresHittable: false))
        XCTAssertEqual(title.label, "附近在招募")
        let apply = app.buttons["nearby.w208.recruit.501"]
        XCTAssertTrue(revealFixtureElement(apply, in: app))
        XCTAssertTrue(apply.label.contains("可申请"), apply.label)
        XCTAssertTrue(app.buttons["nearby.w208.recruit.504"].exists)
        XCTAssertFalse(app.buttons["nearby.w208.recruit.502"].exists, "Applied/joined teams are not recruiting rows")
        apply.tap()
        XCTAssertTrue(element("nearby.w208.header", app).waitForExistence(timeout: 3))
        XCTAssertTrue(revealFixtureElement(element("nearby.team.501", app), in: app, requiresHittable: false))
    }

    func testEnglishCopyForRangeAndMyTeams() {
        let app = launch(language: "en")
        let range = element("nearby.w208.range", app)
        XCTAssertTrue(revealFixtureElement(range, in: app, requiresHittable: false))
        XCTAssertTrue(range.label.hasPrefix("Range "), range.label)
        let mine = app.buttons["nearby.w208.myTeams"]
        XCTAssertTrue(revealFixtureElement(mine, in: app))
        mine.tap()
        XCTAssertTrue(revealFixtureElement(element("nearby.mine.group.leading", app), in: app, requiresHittable: false))
    }
}
