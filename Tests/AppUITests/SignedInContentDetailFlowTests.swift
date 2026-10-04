import XCTest

final class SignedInContentDetailFlowTests: XCTestCase {
    private var launchedApp: XCUIApplication?
    override func tearDown() {
        attachFailureScreenshot(self, app: launchedApp)
        launchedApp?.terminate()
        launchedApp = nil
        super.tearDown()
    }
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ options: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        launchedApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "signedInContentDetail", "-AppleLanguages", "(\(language))", "-AppleLocale", language] + options
        app.launch()
        XCTAssertTrue(app.buttons["homeFeed.recommended.topic.31"].waitForExistence(timeout: 8))
        return app
    }
    private func openTopic(_ app: XCUIApplication) {
        app.buttons["homeFeed.recommended.topic.31"].tap()
    }
    private func openActivityRoute(_ app: XCUIApplication) {
        app.tabBars.buttons["Activities"].tap()
        let card = app.buttons["activity.row.21"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let route = app.buttons["activity.openTopic"]
        XCTAssertTrue(route.waitForExistence(timeout: 5)); route.tap()
    }
    func testActivityTopicRouteBackAndReopen() {
        let app = launch()
        openActivityRoute(app)
        XCTAssertTrue(app.staticTexts["Synthetic route detail"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let route = app.buttons["activity.openTopic"]
        XCTAssertTrue(route.waitForExistence(timeout: 5)); route.tap()
        XCTAssertTrue(app.staticTexts["Synthetic route detail"].waitForExistence(timeout: 5))
    }
    func testActivityTopicRouteClearsOnRoleChangeAndSignOut() {
        let app = launch()
        openActivityRoute(app)
        XCTAssertTrue(app.staticTexts["Synthetic route detail"].waitForExistence(timeout: 5))
        app.buttons["contentDetail.fixture.role"].tap()
        // Revision replacement refreshes scoped content; it does not promise a pop.
        // Run 96's failure AX showed this route still pushed with a fresh merchant read.
        XCTAssertTrue(app.staticTexts["Synthetic merchant route"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic route detail"].exists)
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.requests"].label, "3")
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.identity"].label, "signed-in")
        attachFixtureScreenshot(self, app: app, name: "Activity topic refreshed after role change")
        app.navigationBars["Route details"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Synthetic activity detail"].waitForExistence(timeout: 5))
        let route = app.buttons["activity.openTopic"]
        XCTAssertTrue(route.waitForExistence(timeout: 5)); route.tap()
        XCTAssertTrue(app.staticTexts["Synthetic merchant route"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic route detail"].exists)
        let reopenedReads = Int(app.staticTexts["contentDetail.fixture.requests"].label) ?? 0
        XCTAssertGreaterThan(reopenedReads, 3, "Back/reopen must make a fresh scoped read")
        app.buttons["contentDetail.fixture.signOut"].tap()
        let identity = app.staticTexts["contentDetail.fixture.identity"]
        let signedOut = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "guest"), object: identity)
        XCTAssertEqual(XCTWaiter.wait(for: [signedOut], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(app.staticTexts["Synthetic merchant route"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic route detail"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic activity detail"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["topic.detail.content"].firstMatch.exists)
        XCTAssertFalse(app.buttons["activity.openTopic"].exists)
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.requests"].label, String(reopenedReads), "Sign-out must not dispatch a detail read")
        attachFixtureScreenshot(self, app: app, name: "Activity topic cleared after sign-out")
    }
    func testActivityTopicFailureStaysInTopicAndBackReopens() {
        let app = launch(["--content-detail-topic-failure"])
        openActivityRoute(app)
        XCTAssertTrue(app.descendants(matching: .any)["topic.error"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic route detail"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        let route = app.buttons["activity.openTopic"]
        XCTAssertTrue(route.waitForExistence(timeout: 5)); route.tap()
        XCTAssertTrue(app.descendants(matching: .any)["topic.error"].firstMatch.waitForExistence(timeout: 5))
    }
    func testHomeTopicShelfOpensExactActivityDetailAndBackReopens() {
        let app = launch()
        openTopic(app)
        XCTAssertTrue(app.staticTexts["Synthetic route detail"].waitForExistence(timeout: 5))
        let activity = app.buttons["topic.activity.21"]
        XCTAssertTrue(revealFixtureElement(activity, in: app)); activity.tap()
        XCTAssertTrue(app.staticTexts["Synthetic activity detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity.openRegistration"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Synthetic route detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(revealFixtureElement(activity, in: app)); activity.tap()
        XCTAssertTrue(app.staticTexts["Synthetic activity detail"].waitForExistence(timeout: 5))
    }
    func testActivitiesCardUsesNormalSessionDetailAndRetry() {
        let app = launch(["--content-detail-fail-once"])
        app.tabBars.buttons["Activities"].tap()
        let card = app.buttons["activity.row.21"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let retry = app.buttons["activity.detail.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic activity detail"].exists)
        retry.tap()
        XCTAssertTrue(app.staticTexts["Synthetic activity detail"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.requests"].label, "2")
    }
    func testTopicActivityClubGateNeverShowsFullDetailOrActions() {
        let app = launch(["--content-detail-club-gate"])
        openTopic(app)
        let activity = app.buttons["topic.activity.21"]
        XCTAssertTrue(revealFixtureElement(activity, in: app)); activity.tap()
        XCTAssertTrue(app.staticTexts["activity.detail.clubGate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Join the synthetic club first"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic activity detail"].exists)
        XCTAssertFalse(app.buttons["activity.openRegistration"].exists)
        XCTAssertFalse(app.buttons["activity.openPlay"].exists)
        XCTAssertFalse(app.buttons["activity.openTopic"].exists)
    }
    func testGuestCardsShowSignInWithZeroDetailRequests() {
        let app = launch(["--content-detail-guest"])
        openTopic(app)
        XCTAssertTrue(app.descendants(matching: .any)["topic.detail.signIn"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.requests"].label, "0")
        app.tabBars.buttons["Activities"].tap()
        let card = app.buttons["activity.row.21"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        XCTAssertTrue(app.descendants(matching: .any)["activity.detail.signIn"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.requests"].label, "0")
    }
    func testHomeListApprovalAloneDoesNotGrantDetail() {
        let app = launch(["--content-detail-unapproved"])
        openTopic(app)
        XCTAssertTrue(app.descendants(matching: .any)["topic.error"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.requests"].label, "0")
        XCTAssertFalse(app.staticTexts["Synthetic route detail"].exists)
    }
    func testEmptyShelfChineseAndRoleChangeClearProjection() {
        let app = launch(["--content-detail-empty-shelf"], language: "zh-Hans")
        openTopic(app)
        XCTAssertTrue(app.staticTexts["topic.activities.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["topic.activity.21"].exists)
        app.buttons["contentDetail.fixture.role"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic merchant route"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic route detail"].exists)
        app.buttons["contentDetail.fixture.signOut"].tap()
        XCTAssertFalse(app.staticTexts["Synthetic merchant route"].exists)
    }
    func testDismissedTopicRetryCannotExpireTheCurrentSessionAndReopenStillWorks() {
        let app = launch(["--content-detail-pause-retry"])
        openTopic(app)
        let error = app.descendants(matching: .any)["topic.error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        // SwiftUI propagates topic.error to sibling label leaves and Retry.
        // The first Any match is the error image, not a button container.
        let retryButtons = app.buttons.matching(identifier: "topic.error")
        XCTAssertEqual(retryButtons.count, 1, app.debugDescription)
        let retry = retryButtons.element(boundBy: 0)
        XCTAssertTrue(retry.isEnabled); XCTAssertTrue(retry.isHittable); retry.tap()
        let release = app.buttons["contentDetail.fixture.release401"]
        XCTAssertTrue(release.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["homeFeed.recommended.topic.31"].waitForExistence(timeout: 5))
        release.tap()
        openTopic(app)
        XCTAssertTrue(app.staticTexts["Synthetic route detail"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.identity"].label, "signed-in")
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.requests"].label, "3")
    }
    func testDismissedActivityRetryCannotExpireTheCurrentSessionAndReopenStillWorks() {
        let app = launch(["--content-detail-pause-retry"])
        app.tabBars.buttons["Activities"].tap()
        let card = app.buttons["activity.row.21"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let retry = app.buttons["activity.detail.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        let release = app.buttons["contentDetail.fixture.release401"]
        XCTAssertTrue(release.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5)); release.tap(); card.tap()
        XCTAssertTrue(app.staticTexts["Synthetic activity detail"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.identity"].label, "signed-in")
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.requests"].label, "3")
    }
    func testCurrent403ShowsErrorWithoutSigningOutOrRenderingDetail() {
        let app = launch(["--content-detail-forbidden"])
        openTopic(app)
        XCTAssertTrue(app.descendants(matching: .any)["topic.error"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic route detail"].exists)
        app.tabBars.buttons["Activities"].tap()
        let card = app.buttons["activity.row.21"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        XCTAssertTrue(app.staticTexts["activity.detail.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic activity detail"].exists)
        XCTAssertEqual(app.staticTexts["contentDetail.fixture.identity"].label, "signed-in")
    }
    func testUnknownShelfDoesNotClaimNoActivities() {
        let app = launch(["--content-detail-unknown-shelf"])
        openTopic(app)
        XCTAssertTrue(app.staticTexts["Synthetic route detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["topic.activities.empty"].exists)
        XCTAssertFalse(app.buttons["topic.activity.21"].exists)
    }

}
