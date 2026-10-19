import XCTest

/// Synthetic offline passport tools (那年今日 / 月度回顾). No account, network or location.
final class RoamPassportToolsFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String = "content") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-roam-experience", "--uitesting-roam-experience-scenario", scenario,
            "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func open(_ id: String, _ app: XCUIApplication) {
        XCTAssertTrue(element("roam.experience.hub", app).waitForExistence(timeout: 8))
        let target = app.buttons[id]; XCTAssertTrue(revealFixtureElement(target, in: app)); target.tap()
    }

    func testAnniversaryShowsPastYearsNewestFirstAndReturnsToHub() {
        let app = app()
        open("roam.tools.anniversary.open", app)
        let rows = app.descendants(matching: .any).matching(identifier: "roam.tools.anniversary.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.element(boundBy: 0).label.contains("1 yr ago"), rows.element(boundBy: 0).label)
        XCTAssertTrue(rows.element(boundBy: 1).label.contains("3 yr ago"), rows.element(boundBy: 1).label)
        XCTAssertTrue(element("roam.tools.anniversary.change", app).exists)
        XCTAssertFalse(element("roam.tools.anniversary.empty", app).exists)
        XCTAssertFalse(element("roam.tools.anniversary.error", app).exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("roam.experience.hub", app).waitForExistence(timeout: 5))
    }

    func testMonthlyRecapCountsWeeksKindsAndMonthBounds() {
        let app = app()
        open("roam.tools.recap.open", app)
        XCTAssertTrue(element("roam.tools.recap.routes", app).waitForExistence(timeout: 5))
        let routesHero = element("roam.tools.recap.routes", app).label
        XCTAssertTrue(routesHero.hasPrefix("3") && routesHero.contains("route completions"), routesHero)
        XCTAssertTrue(element("roam.tools.recap.weeks", app).exists)
        XCTAssertFalse(app.buttons["roam.tools.recap.next"].isEnabled, "Current month cannot move into the future")
        for title in ["老城墙夜行", "滨江骑行路线", "梧桐街区漫步"] {
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "roam.tools.recap.row", title)).firstMatch
            XCTAssertTrue(revealFixtureElement(row, in: app, requiresHittable: false), title)
        }
        let rows = app.descendants(matching: .any).matching(identifier: "roam.tools.recap.row")
        let picker = element("roam.tools.recap.kindPicker", app)
        XCTAssertTrue(revealFixtureElement(picker, in: app, towardTop: true))
        picker.buttons["City stamps"].tap()
        XCTAssertTrue(app.staticTexts["City stamps by week"].waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        let previous = app.buttons["roam.tools.recap.previous"]
        XCTAssertTrue(revealFixtureElement(previous, in: app, towardTop: true)); previous.tap()
        XCTAssertTrue(app.buttons["roam.tools.recap.next"].waitForEnabled(timeout: 5))
    }

    func testEmptyToolsShowHonestEmptyStates() {
        let app = app("empty")
        open("roam.tools.anniversary.open", app)
        XCTAssertTrue(element("roam.tools.anniversary.empty", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("roam.tools.anniversary.row", app).exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        open("roam.tools.recap.open", app)
        XCTAssertTrue(revealFixtureElement(element("roam.tools.recap.empty", app), in: app, requiresHittable: false))
        XCTAssertFalse(element("roam.tools.recap.weeks", app).exists)
        XCTAssertFalse(element("roam.tools.recap.error", app).exists)
    }
}

private extension XCUIElement {
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
