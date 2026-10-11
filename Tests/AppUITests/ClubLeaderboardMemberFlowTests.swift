import XCTest

final class ClubLeaderboardMemberFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: runningApp)
        runningApp?.terminate(); runningApp = nil
    }
    private func open(_ name: String, app: XCUIApplication) -> Bool {
        let root = app.collectionViews["club.gov.fixture.root"]
        guard root.waitForExistence(timeout: 5) else {
            attachFixtureScreenshot(self, app: app, name: "Club fixture root not ready")
            XCTFail(app.debugDescription); return false
        }
        let button = root.buttons["club.gov.fixture." + name]
        guard revealFixtureElement(button, in: app), button.exists, button.isEnabled, button.isHittable else {
            attachFixtureScreenshot(self, app: app, name: "Club fixture entry unreachable")
            XCTFail(app.debugDescription); return false
        }
        button.tap()
        let destination = app.descendants(matching: .any)["club.gov.fixture.destination." + name].firstMatch
        guard destination.waitForExistence(timeout: 5) else {
            // Never search or scroll the old root after an unacknowledged navigation tap.
            attachFixtureScreenshot(self, app: app, name: "Club fixture destination missing after one tap")
            XCTFail(app.debugDescription); return false
        }
        return true
    }
    private func fact(_ key: String, containing text: String, app: XCUIApplication) -> XCUIElement {
        // LabeledContent exposes its label and value together on some iOS versions.
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND (label CONTAINS %@ OR value CONTAINS %@)",
            "club.gov.fact." + key, text, text)).firstMatch
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let revealed = revealFixtureElement(element, in: app)
        if !revealed { attachFixtureScreenshot(self, app: app, name: "Unreachable club governance control") }
        XCTAssertTrue(revealed, app.debugDescription)
    }
    private func tap(_ identifier: String, app: XCUIApplication) {
        let element = app.buttons[identifier]
        reveal(element, app: app)
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable); element.tap()
    }
    // Real ClubGovernanceReadView -> SocialPublicProfileView navigation. These
    // authored simulator scenarios are NOT_RUN in the Linux delivery.
    private func launchLeaderboard(_ scenario: String = "content") -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-club-governance",
            "--club-leaderboard-scenario", scenario, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); return app
    }
    func testLeaderboardMemberPublicProfileBackAndReopen() {
        let app = launchLeaderboard(); guard open("leaderboard", app: app) else { return }
        for _ in 0..<2 {
            tap("club.gov.leaderboard.profile.704", app: app)
            XCTAssertTrue(app.staticTexts["Example city explorer"].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.descendants(matching: .any)["social.profile"].firstMatch.exists)
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons["club.gov.leaderboard.profile.704"].waitForExistence(timeout: 5), app.debugDescription)
        }
    }
    func testLeaderboardAccountSwitchRetiresVisiblePublicProfile() {
        let app = launchLeaderboard(); guard open("leaderboard", app: app) else { return }
        tap("club.gov.leaderboard.profile.704", app: app)
        let profile = app.staticTexts["Example city explorer"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        app.buttons["club.gov.leaderboard.fixture.switch"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: profile)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(app.staticTexts["club.gov.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.gov.leaderboard.profile.704"].exists)
    }
    private func waitLeaderboardCounter(_ identifier: String, equals value: String, app: XCUIApplication) {
        let counter = app.staticTexts["club.gov.leaderboard.fixture." + identifier]
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", value), object: counter)
        XCTAssertEqual(XCTWaiter.wait(for: [reached], timeout: 5), .completed, app.debugDescription)
    }
    func testLeaderboardSwitchDuringProfileLoadRejectsLatePresentation() {
        let app = launchLeaderboard("heldProfile"); guard open("leaderboard", app: app) else { return }
        defer {
            // Also drain a held request on a failed assertion before app teardown.
            let cleanup = app.buttons["club.gov.leaderboard.fixture.releaseProfile"]
            if cleanup.exists && cleanup.isEnabled && cleanup.isHittable { cleanup.tap() }
        }
        tap("club.gov.leaderboard.profile.704", app: app)
        // Prove this exact request is in flight before switching the account.
        // The fixture cannot finish it through elapsed time or cancellation.
        waitLeaderboardCounter("profileStarted", equals: "1", app: app)
        waitLeaderboardCounter("profilePending", equals: "1", app: app)
        waitLeaderboardCounter("profileReturned", equals: "0", app: app)
        let oldProfile = app.staticTexts["Held profile from account 701"]
        XCTAssertFalse(oldProfile.exists)
        app.buttons["club.gov.leaderboard.fixture.switch"].tap()
        let error = app.staticTexts["club.gov.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.isHittable, app.debugDescription)
        waitLeaderboardCounter("profilePending", equals: "1", app: app)
        let release = app.buttons["club.gov.leaderboard.fixture.releaseProfile"]
        XCTAssertTrue(release.exists && release.isEnabled && release.isHittable, app.debugDescription)
        release.tap()
        // Observe the old-account call actually returning after destination
        // retirement; merely cancelling or dropping it cannot satisfy this test.
        waitLeaderboardCounter("profileReturned", equals: "1", app: app)
        waitLeaderboardCounter("returnedAccount", equals: "701", app: app)
        waitLeaderboardCounter("returnedMember", equals: "704", app: app)
        waitLeaderboardCounter("profilePending", equals: "0", app: app)
        let late = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: oldProfile)
        late.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 2), .completed, app.debugDescription)
        XCTAssertFalse(app.buttons["club.gov.leaderboard.profile.704"].exists)
    }
    func testLeaderboardMissingProfileReaderKeepsReadOnlyFacts() {
        let app = launchLeaderboard("missingProfile"); guard open("leaderboard", app: app) else { return }
        XCTAssertTrue(fact("nickname", containing: "Fixture member", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.gov.leaderboard.profile.704"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["social.profile"].firstMatch.exists)
    }
    func testLeaderboardMismatchedProfileAccountCannotOpenMember() {
        let app = launchLeaderboard("wrongProfileAccount"); guard open("leaderboard", app: app) else { return }
        XCTAssertTrue(fact("nickname", containing: "Fixture member", app: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["club.gov.leaderboard.profile.704"].exists)
    }
    func testLeaderboardMissingMemberIDCannotCreateDestination() {
        let app = launchLeaderboard("missingMemberID"); guard open("leaderboard", app: app) else { return }
        XCTAssertTrue(app.staticTexts["club.gov.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "club.gov.leaderboard.profile.")).firstMatch.exists)
    }

}
