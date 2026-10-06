import XCTest

/// Synthetic UI acceptance authored here; execution needs an Apple simulator.
final class MerchantClubDiscoveryFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil
    }
    private func launch(_ scenario: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-club-fixture", scenario,
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch(); return app
    }
    private func element(_ identifier: String, app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }
    private func tap(_ identifier: String, app: XCUIApplication, towardTop: Bool = false) {
        let value = app.buttons[identifier]
        XCTAssertTrue(revealFixtureElement(value, in: app, towardTop: towardTop), app.debugDescription)
        XCTAssertTrue(value.isEnabled); XCTAssertTrue(value.isHittable); value.tap()
    }
    // These synthetic controls live ABOVE the NavigationStack. Content scrolling
    // cannot reveal them; validate their unique native leaf in the fixed header.
    private func tapFixedFixtureControl(_ identifier: String, app: XCUIApplication) {
        let allowed = ["club.fixture.toggleLocalityRole", "club.fixture.switchMerchant",
                       "club.fixture.locality.release", "club.fixture.locality.fail"]
        guard allowed.contains(identifier) else { XCTFail("Not a fixed fixture control"); return }
        let query = app.buttons.matching(identifier: identifier)
        let notice = app.staticTexts["club.fixture.notice"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard query.count == 1, notice.exists,
                  let bar = app.navigationBars.allElementsBoundByIndex.first(where: { $0.exists && !$0.frame.isEmpty }) else { return false }
            let button = query.element(boundBy: 0), frame = button.frame
            return button.exists && button.isEnabled && button.isHittable && !frame.isEmpty &&
                app.frame.contains(frame) && frame.minY >= notice.frame.maxY && frame.maxY <= bar.frame.minY
        }, object: app)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            XCTFail("Expected one enabled fixed-header fixture control: " + app.debugDescription); return
        }
        query.element(boundBy: 0).tap()
    }
    private func pending(_ count: Int, app: XCUIApplication) {
        let countElement = element("club.fixture.locality.pending", app: app)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", String(count)), object: countElement)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, app.debugDescription)
    }
    func testMerchantLocalityHidesOwnedJoinedAndKeepsDetailReturn() {
        let app = launch("merchantLocality", language: "zh-Hans")
        XCTAssertTrue(element("club.home.locality.ready", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.openOwned"].exists)
        XCTAssertFalse(element("club.home.owned.81", app: app).exists)
        XCTAssertFalse(element("club.home.joined.82", app: app).exists)
        XCTAssertFalse(element("club.home.nearby.84", app: app).exists)
        tap("club.home.nearby.83", app: app)
        XCTAssertTrue(app.staticTexts["Locality fixture club 83"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(element("club.home.locality.ready", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("club.home.nearby.83", app: app).exists)
    }
    func testUnknownLocalityKeepsAllNearbyWithRetryThenFilters() {
        let app = launch("merchantLocalityUnknown")
        XCTAssertTrue(app.buttons["club.home.locality.retry"].waitForExistence(timeout: 5))
        XCTAssertTrue(revealFixtureElement(element("club.home.nearby.84", app: app), in: app))
        // The nearby row is below the retry section; lazy List may remove that button from AX.
        tap("club.home.locality.retry", app: app, towardTop: true)
        XCTAssertTrue(element("club.home.locality.ready", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("club.home.nearby.84", app: app).exists)
        XCTAssertTrue(element("club.home.nearby.83", app: app).exists)
    }
    func testLocalityNetworkFailureKeepsAllNearbyAndNoMatchIsHonest() {
        var app = launch("merchantLocalityRetry")
        XCTAssertTrue(app.buttons["club.home.locality.retry"].waitForExistence(timeout: 5))
        XCTAssertTrue(revealFixtureElement(element("club.home.nearby.84", app: app), in: app))
        // The nearby row is below the retry section; lazy List may remove that button from AX.
        tap("club.home.locality.retry", app: app, towardTop: true)
        XCTAssertTrue(element("club.home.locality.ready", app: app).waitForExistence(timeout: 5))
        app.terminate(); app = launch("merchantLocalityEmpty")
        XCTAssertTrue(element("club.home.locality.ready", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("club.home.nearby.empty", app: app).exists)
        XCTAssertFalse(app.buttons["club.home.locality.retry"].exists)
    }
    func testLateLocalityAfterPlayerSwitchCannotHidePlayerRows() {
        let app = launch("merchantLocalityDelayed"); pending(1, app: app)
        tapFixedFixtureControl("club.fixture.toggleLocalityRole", app: app)
        XCTAssertTrue(app.buttons["club.openOwned"].waitForExistence(timeout: 5))
        tapFixedFixtureControl("club.fixture.locality.release", app: app); pending(0, app: app)
        XCTAssertFalse(element("club.home.locality.ready", app: app).exists)
        XCTAssertFalse(app.buttons["club.home.locality.retry"].exists)
        XCTAssertTrue(revealFixtureElement(element("club.home.owned.81", app: app), in: app))
        XCTAssertTrue(revealFixtureElement(element("club.home.joined.82", app: app), in: app))
        XCTAssertTrue(revealFixtureElement(element("club.home.nearby.84", app: app), in: app))
    }
    func testMerchantSwitchFencesOldUnauthorizedBeforeNewLocality() {
        let app = launch("merchantLocalityDelayed"); pending(1, app: app)
        tapFixedFixtureControl("club.fixture.switchMerchant", app: app); pending(2, app: app)
        tapFixedFixtureControl("club.fixture.locality.fail", app: app); pending(1, app: app)
        XCTAssertFalse(app.buttons["club.home.locality.retry"].exists)
        tapFixedFixtureControl("club.fixture.locality.release", app: app); pending(0, app: app)
        XCTAssertTrue(element("club.home.locality.ready", app: app).waitForExistence(timeout: 5))
        XCTAssertTrue(revealFixtureElement(element("club.home.nearby.84", app: app), in: app))
        XCTAssertFalse(element("club.home.nearby.83", app: app).exists)
    }
}
