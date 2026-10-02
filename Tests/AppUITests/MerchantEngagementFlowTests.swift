import XCTest

final class MerchantEngagementFlowTests: XCTestCase {
    private func launch(_ scenario: String = "ready", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-merchant-engagement-fixture","--uitesting-merchant-engagement-scenario",scenario,"-AppleLanguages","(\(language))","-AppleLocale",language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) { for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() } }
    private func tap(_ id: String, app: XCUIApplication) { let element = app.buttons[id]; XCTAssertTrue(element.waitForExistence(timeout:5)); reveal(element,app:app); element.tap() }
    private func prepareSegment(_ app: XCUIApplication) {
        tap("merchant.engagement.saveSegment",app:app)
        let input = app.textFields["merchant.engagement.editor.name"]; XCTAssertTrue(input.waitForExistence(timeout:5)); input.tap(); input.typeText("Example segment")
        tap("merchant.engagement.editor.review",app:app)
    }
    func testSavedSegmentAppliesCurrentFilter() {
        let app = launch(); tap("merchant.engagement.segment.71001",app:app)
        XCTAssertTrue(app.textFields["2026-09-01"].exists || app.staticTexts["Example return visitors"].exists)
    }
    func testSegmentReviewCanCancelWithoutSuccess() {
        let app = launch(); prepareSegment(app); tap("merchant.engagement.cancelReview",app:app)
        XCTAssertFalse(app.staticTexts["The segment-save response was received."].exists)
    }
    func testProductionDisabledReviewHasNoConfirmControl() {
        let app = launch("disabled"); prepareSegment(app)
        XCTAssertTrue(app.staticTexts["merchant.engagement.liveDisabled"].waitForExistence(timeout:5)); XCTAssertFalse(app.buttons["merchant.engagement.confirm"].exists)
    }
    func testUnknownMutationSurvivesRefreshWithoutNewSend() {
        let app = launch("unknown"); prepareSegment(app); tap("merchant.engagement.confirm",app:app)
        XCTAssertTrue(app.staticTexts["merchant.engagement.locked"].waitForExistence(timeout:5))
        tap("merchant.engagement.refresh",app:app)
        XCTAssertTrue(app.staticTexts["merchant.engagement.locked"].exists)
    }
    func testCampaignCreationExplainsSeparateDispatch() {
        let app = launch(); tap("merchant.engagement.createCampaign",app:app)
        let title = app.textFields["merchant.engagement.editor.title"]; XCTAssertTrue(title.waitForExistence(timeout:5)); title.tap(); title.typeText("Example title")
        let content = app.descendants(matching:.any)["merchant.engagement.editor.content"]; content.tap(); content.typeText("Example message")
        tap("merchant.engagement.editor.review",app:app)
        XCTAssertTrue(app.descendants(matching:.any)["merchant.engagement.audience"].waitForExistence(timeout:5))
        tap("merchant.engagement.confirm",app:app)
        XCTAssertTrue(app.staticTexts["The task was created. Dispatch requires its own review."].waitForExistence(timeout:5))
    }
    func testInactiveIdentityCanPrepareInvitationWithoutStoreGuess() {
        let app = launch("inactive"); tap("merchant.engagement.acceptInvitation",app:app)
        let field = app.secureTextFields["merchant.engagement.editor.inviteToken"]; XCTAssertTrue(field.waitForExistence(timeout:5)); field.tap(); field.typeText("synthetic-invitation-token")
        tap("merchant.engagement.editor.review",app:app)
        XCTAssertTrue(app.buttons["merchant.engagement.confirm"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["710"].exists)
    }
    func testChineseWorkspaceLocalizesOperations() {
        let app = launch(language:"zh-Hans")
        XCTAssertTrue(app.navigationBars["客户运营"].waitForExistence(timeout:5)); XCTAssertTrue(app.buttons["merchant.engagement.saveSegment"].exists)
    }
    func testSignoutClearsPreviouslyLoadedSegments() {
        let app = launch("sessionChange"); XCTAssertTrue(app.buttons["merchant.engagement.segment.71001"].waitForExistence(timeout:5))
        tap("merchant.engagement.fixtureSignOut",app:app); XCTAssertFalse(app.buttons["merchant.engagement.segment.71001"].exists)
    }
}
