import XCTest

final class SignedInContentDetailFlowTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
    private func launch(_ options: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "signedInContentDetail", "-AppleLanguages", "(\(language))", "-AppleLocale", language] + options
        app.launch()
        XCTAssertTrue(app.buttons["homeFeed.recommended.topic.31"].waitForExistence(timeout: 8))
        return app
    }
    private func openTopic(_ app: XCUIApplication) {
        app.buttons["homeFeed.recommended.topic.31"].tap()
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
        error.buttons.firstMatch.tap()
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
