import XCTest

/// Offline fixtures only. These tests are authored, not runtime-verified in the cloud workspace.
final class SocialAccountFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ destination: String, scenario: String = "content", language: String = "en", extra: [String] = []) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-module", "socialAccount", "--uitesting-social-destination", destination, "--uitesting-social-scenario", scenario] + extra
        app.launch()
    }
    private func text(_ value: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch }
    private func reveal(_ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<8 { if element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func enterReview() {
        let editor = app.textViews["social.editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Synthetic offline draft")
        let done = app.buttons["social.editor.keyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let button = app.buttons["social.editor.review"]; reveal(button); button.tap()
    }
    func testGuestPublicProfileShowsUnknownRelationshipWithoutPostsRequest() {
        launch("profile", scenario: "guest")
        XCTAssertTrue(text("Example city explorer").waitForExistence(timeout: 5))
        XCTAssertTrue(text("Sign in to see your relationship").exists)
        reveal(app.staticTexts["social.profile.postsSignIn"])
        XCTAssertFalse(app.staticTexts["social.noPosts"].exists)
    }
    func testGuideKeepsMeaningfulNumericTitleAndRoutesToRealTabIntent() {
        launch("guide")
        let information = app.buttons["social.information.92"]; reveal(information); information.tap()
        XCTAssertTrue(app.staticTexts["2026"].waitForExistence(timeout: 5))
        XCTAssertTrue(text("Synthetic information body").exists)
    }
    func testInvitePartialRewardAndPagination() {
        launch("invites", scenario: "partial")
        XCTAssertTrue(app.staticTexts["social.invites.partial"].waitForExistence(timeout: 5))
        XCTAssertTrue(text("reward not synchronized").exists)
        let more = app.buttons["social.invites.more"]; reveal(more); more.tap()
        reveal(text("Example earlier member"))
        XCTAssertFalse(text("first purchase pending").exists)
    }
    func testDisabledLiveWriterAllowsReviewButNotSubmission() {
        launch("editor", scenario: "disabled"); enterReview()
        let submit = app.buttons["social.review.disabled"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5)); XCTAssertFalse(submit.isEnabled)
        XCTAssertFalse(app.staticTexts["social.state.acknowledged"].exists)
    }
    func testSyntheticAcknowledgementIsLabelledAndDoesNotInsertPost() {
        launch("editor"); enterReview()
        let confirm = app.buttons["social.review.confirm"]; reveal(confirm); confirm.tap()
        XCTAssertTrue(app.staticTexts["social.state.acknowledged"].waitForExistence(timeout: 5))
        XCTAssertTrue(text("Nothing was sent externally").exists); XCTAssertFalse(confirm.isEnabled)
    }
    func testUncertainOutcomeStaysLockedAfterDismissalAndReturn() {
        launch("editor", scenario: "unknown"); enterReview()
        let confirm = app.buttons["social.review.confirm"]; reveal(confirm); confirm.tap()
        XCTAssertTrue(app.staticTexts["social.state.unknown"].waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.isEnabled)
        app.navigationBars["Review"].buttons["Close"].tap()
        XCTAssertFalse(app.buttons["social.editor.review"].isEnabled)
    }
    func testMediaPreviewLoadsOnlyOnTapAndClearsAfterAccountSwitch() {
        launch("media")
        XCTAssertFalse(app.images["social.media.loaded"].exists)
        let load = app.buttons["social.media.load"]; XCTAssertTrue(load.waitForExistence(timeout: 5)); load.tap()
        XCTAssertTrue(app.images["social.media.loaded"].waitForExistence(timeout: 5))
        app.buttons["social.fixture.switch"].tap()
        XCTAssertFalse(app.images["social.media.loaded"].exists)
        XCTAssertTrue(app.buttons["social.media.load"].exists)
    }
    func testChineseGuideWithAccessibilityTextHasTranslatedDestinations() {
        launch("guide", language: "zh-Hans", extra: ["--uitesting-large-text"])
        XCTAssertTrue(text("探索方式").waitForExistence(timeout: 5))
        XCTAssertFalse(text("social.guide.classic").exists)
        let roam = app.buttons["social.guide.roam"]; reveal(roam); roam.tap()
        XCTAssertTrue(text("Fixture destination: roam").exists)
    }
    func testDraftSurvivesNestedReviewAndCancelThenDiscardReopensEmpty() {
        launch("editorSheet")
        let open = app.buttons["social.fixture.openEditor"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        enterReview()
        let closeReview = app.buttons["social.review.close"]
        XCTAssertTrue(closeReview.waitForExistence(timeout: 5)); closeReview.tap()
        let editor = app.textViews["social.editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Synthetic offline draft")
        app.buttons["social.editor.close"].tap()
        let keep = app.buttons["social.editor.keepEditing"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5)); keep.tap()
        XCTAssertEqual(editor.value as? String, "Synthetic offline draft")
        attachFixtureScreenshot(self, app: app, name: "Social draft preserved after nested review and cancel")
        app.buttons["social.editor.close"].tap()
        app.buttons["social.editor.discard"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "")
    }
    func testChineseLargeTextDraftCancelKeepsTextAndKeyboardDismisses() {
        launch("editorSheet", language: "zh-Hans", extra: ["--uitesting-large-text", "--uitesting-dark-mode"])
        let open = app.buttons["social.fixture.openEditor"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let editor = app.textViews["social.editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Native draft")
        let done = app.buttons["social.editor.keyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["social.editor.close"].tap()
        let keep = app.buttons["social.editor.keepEditing"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5)); XCTAssertEqual(keep.label, "继续编辑"); keep.tap()
        XCTAssertEqual(editor.value as? String, "Native draft")
        attachFixtureScreenshot(self, app: app, name: "Chinese social draft large text dark mode after keyboard dismissal")
    }

}
