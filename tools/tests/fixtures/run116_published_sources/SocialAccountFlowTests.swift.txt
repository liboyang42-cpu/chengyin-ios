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
    private func keepDraft(_ expected: String, dialogTitle: String) {
        let dialog = app.sheets.matching(NSPredicate(format: "label == %@", dialogTitle)).firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), app.debugDescription)
        let keep = dialog.buttons["social.editor.keepEditing"]
        if keep.exists && keep.isHittable { keep.tap() }
        else { dismissFixtureConfirmationPopover(in: app) }
        // Wait only for the presentation transition. An absent-sheet AX lookup can
        // consume most of this bound; polling unrelated editor queries in the same
        // predicate can time out even when the full draft is already restored.
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: dialog)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, app.debugDescription)
        let editor = app.textViews["social.editor.text"]
        XCTAssertTrue(editor.exists, app.debugDescription)
        XCTAssertEqual(editor.value as? String, expected, app.debugDescription)
        let review = app.buttons["social.editor.review"]
        XCTAssertTrue(review.exists, app.debugDescription)
        XCTAssertTrue(review.isEnabled, app.debugDescription)
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
        assertFixtureEnvironment(in: app, dynamicTypeSize: "accessibility3")
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
        keepDraft("Synthetic offline draft", dialogTitle: "Discard this draft?")
        XCTAssertEqual(editor.value as? String, "Synthetic offline draft")
        attachFixtureScreenshot(self, app: app, name: "Social draft preserved after nested review and cancel")
        app.buttons["social.editor.close"].tap()
        let discard = app.sheets.matching(NSPredicate(format: "label == %@", "Discard this draft?")).firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        tapFixtureSheetAction("Discard draft", in: discard, app: app)
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "")
    }
    func testChineseLargeTextDraftCancelKeepsTextAndKeyboardDismisses() {
        launch("editorSheet", language: "zh-Hans", extra: ["--uitesting-large-text", "--uitesting-dark"])
        assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility3")
        let open = app.buttons["social.fixture.openEditor"]
        XCTAssertTrue(open.waitForExistence(timeout: 5)); open.tap()
        let editor = app.textViews["social.editor.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("Native draft")
        let done = app.buttons["social.editor.keyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["social.editor.close"].tap()
        keepDraft("Native draft", dialogTitle: "要放弃这份草稿吗？")
        XCTAssertEqual(editor.value as? String, "Native draft")
        attachFixtureScreenshot(self, app: app, name: "Chinese social draft large text dark mode after keyboard dismissal")
    }

    func testHTMLArticleIsReadableInertAndReopensAfterBack() {
        launch("guide", scenario: "articleHTML")
        let row = app.buttons["social.information.91"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "social.information.91").count, 1, app.debugDescription)
        XCTAssertTrue(revealFixtureElement(row, in: app), app.debugDescription)
        XCTAssertTrue(row.isEnabled, app.debugDescription); row.tap()
        XCTAssertTrue(text("Synthetic article heading").waitForExistence(timeout: 5))
        reveal(text("Readable bold text & 中文."))
        reveal(text("First instruction"))
        reveal(text("Second instruction"))
        let label = text("Inert article link"); reveal(label); label.tap()
        XCTAssertTrue(app.otherElements["social.information.detail"].exists || text("Inert article link").exists)
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertFalse(app.links["Inert article link"].exists)
        XCTAssertFalse(text("FORBIDDEN_SCRIPT_TEXT").exists)
        XCTAssertFalse(text("<h2>").exists)
        reveal(app.staticTexts["social.article.limited"])
        app.navigationBars.buttons["Play guide"].tap()
        // Back can restore a partly clipped row that still reports isHittable.
        // Use the existing complete-viewport guard before the same single native tap.
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons.matching(identifier: "social.information.91").count, 1, app.debugDescription)
        XCTAssertTrue(revealFixtureElement(row, in: app), app.debugDescription)
        XCTAssertTrue(row.isEnabled, app.debugDescription); row.tap()
        XCTAssertTrue(text("Synthetic article heading").waitForExistence(timeout: 5))
    }
    func testChineseLargeTextArticleReplacesOldContentAfterAccountSwitch() {
        launch("guide", scenario: "articleHTML", language: "zh-Hans", extra: ["--uitesting-large-text", "--uitesting-dark"])
        assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility3")
        let row = app.buttons["social.information.91"]; reveal(row); row.tap()
        XCTAssertTrue(text("示例正文标题").waitForExistence(timeout: 5))
        reveal(app.staticTexts["social.article.limited"])
        XCTAssertEqual(app.staticTexts["social.article.limited"].label, "部分文章内容无法显示。")
        app.buttons["social.fixture.switch"].tap()
        XCTAssertFalse(text("示例正文标题").exists)
        // Reopen if SwiftUI discarded the old destination with its owning list;
        // otherwise the existing detail must reload under the new identity.
        if row.waitForExistence(timeout: 3) { reveal(row); row.tap() }
        XCTAssertTrue(text("替换正文标题").waitForExistence(timeout: 5))
        XCTAssertFalse(text("示例正文标题").exists)
        attachFixtureScreenshot(self, app: app, name: "Chinese article large text after identity replacement")
    }
    func testArticleRemovedEmptyAndReadFailureKeepExistingRecovery() {
        launch("guide", scenario: "removed")
        var row = app.buttons["social.information.91"]; reveal(row); row.tap()
        XCTAssertTrue(text("This guide is no longer available").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["social.article.block.0"].exists)
        app.terminate()
        launch("guide", scenario: "articleEmpty")
        row = app.buttons["social.information.91"]; reveal(row); row.tap()
        XCTAssertTrue(text("This guide does not have readable content yet").waitForExistence(timeout: 5))
        app.terminate()
        launch("guide", scenario: "articleRetry")
        row = app.buttons["social.information.91"]; reveal(row); row.tap()
        XCTAssertTrue(text("Unable to load this information").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["social.article.block.0"].exists)
        app.buttons["Retry"].tap()
        XCTAssertTrue(text("Synthetic article heading").waitForExistence(timeout: 5))
    }

}
