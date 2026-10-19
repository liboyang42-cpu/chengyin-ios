import XCTest

/// Mini-program pages/roam/index 开始漫游 / 漫游护照 home in the DEBUG-only `--uitesting-roam-home` host.
/// Synthetic readers only; no account, network, location or write.
final class RoamHomeTabsFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func launch(_ scenario: String = "content", language: String = "zh-Hans") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-home", "--uitesting-roam-home-scenario", scenario, "--uitesting-reset-language",
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testStartTabShowsIntroCardsPeekAndActivitySheetTeamRoute() {
        let app = launch()
        let tabs = app.segmentedControls["roam.home.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 8))
        XCTAssertTrue(tabs.buttons["开始漫游"].exists)
        XCTAssertTrue(tabs.buttons["漫游护照"].exists)
        XCTAssertTrue(revealFixtureElement(element("roam.home.intro.map", app), in: app, requiresHittable: false))
        XCTAssertTrue(element("roam.home.intro.teams", app).exists)
        let card = element("roam.home.peek.card.activity-901", app)
        XCTAssertTrue(revealFixtureElement(card, in: app))
        XCTAssertTrue(element("roam.home.peek.card.topic-802", app).exists)
        XCTAssertFalse(element("roam.home.peek.card.hangout-7", app).exists, "Retired hangout rows are dropped")
        card.tap()
        XCTAssertTrue(element("roam.home.sheet", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("roam.home.sheet.participants", app).label.contains("2 人参加"), element("roam.home.sheet.participants", app).label)
        XCTAssertTrue(element("roam.home.sheet.createTeam", app).exists, "A linked team ticket counts as registered")
        let team = element("roam.home.sheet.team.501", app)
        XCTAssertTrue(revealFixtureElement(team, in: app))
        team.tap()
        XCTAssertTrue(element("roam.home.fixture.team", app).waitForExistence(timeout: 5))
    }

    func testPassportTabShowsTilesClosedEventAndUnavailableTools() {
        let app = launch(language: "en")
        let tabs = app.segmentedControls["roam.home.tabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 8))
        tabs.buttons["Roam passport"].tap()
        XCTAssertTrue(element("roam.home.passport", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("roam.home.passport.stat.trips", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("roam.home.passport.tile.history", app).label.contains("trips"), element("roam.home.passport.tile.history", app).label)
        XCTAssertTrue(element("roam.home.passport.tile.goals", app).label.contains("NEW"))
        let event = element("roam.home.passport.play.event", app)
        XCTAssertTrue(revealFixtureElement(event, in: app, requiresHittable: false))
        XCTAssertTrue(event.label.contains("Not open yet"), event.label)
        let goals = app.buttons["roam.home.passport.tile.goals"]
        XCTAssertTrue(revealFixtureElement(goals, in: app, towardTop: true))
        goals.tap()
        XCTAssertTrue(element("roam.home.tool.unavailable", app).waitForExistence(timeout: 5))
    }

    func testPeekSignInAndDeniedStates() {
        var app = launch("login")
        XCTAssertTrue(revealFixtureElement(element("roam.home.peek.login", app), in: app, requiresHittable: false))
        XCTAssertTrue(app.staticTexts["登录后查看附近活动与队伍"].exists)
        app.terminate()
        app = launch("denied")
        XCTAssertTrue(revealFixtureElement(element("roam.home.peek.denied", app), in: app, requiresHittable: false))
        app.terminate()
        app = launch("empty")
        XCTAssertTrue(revealFixtureElement(element("roam.home.peek.empty", app), in: app, requiresHittable: false))
        XCTAssertTrue(app.staticTexts["附近暂无活动"].exists)
    }
}
