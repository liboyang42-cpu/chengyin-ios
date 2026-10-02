import XCTest

final class MerchantEngagementFlowTests: XCTestCase {
    private var currentApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: currentApp)
        if let app = currentApp, (testRun?.totalFailureCount ?? 0) > 0 {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Merchant engagement failure hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        currentApp?.terminate(); currentApp = nil
    }
    private func cancelReview(_ app: XCUIApplication) {
        tap("merchant.engagement.cancelReview", app: app)
        // Native sheet dismissal is asynchronous. Require the same strict outcome,
        // rather than reading a transitional accessibility snapshot immediately.
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.buttons["merchant.engagement.confirm"].exists
                && !app.buttons["merchant.engagement.cancelReview"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed, app.debugDescription)
        XCTAssertFalse(app.buttons["merchant.engagement.confirm"].exists)
        XCTAssertFalse(app.staticTexts["The segment-save response was received."].exists)
        XCTAssertFalse(app.staticTexts["已收到保存分群回执。"].exists)
    }
    private func launch(_ scenario: String = "ready", language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language","--uitesting-merchant-engagement-fixture","--uitesting-merchant-engagement-scenario",scenario,"-AppleLanguages","(\(language))","-AppleLocale",language == "en" ? "en_US" : "zh_CN"]
        currentApp = app
        app.launch()
        let title = language == "en" ? "CRM operations" : "客户运营"
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), app.debugDescription)
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, towardTop: Bool = false) {
        XCTAssertTrue(revealFixtureElement(element, in: app, towardTop: towardTop, maximumSwipes: 16), app.debugDescription)
    }
    private func tap(_ id: String, app: XCUIApplication) {
        let element = app.buttons[id]
        // List rows may not exist in the accessibility tree until scrolled into view.
        reveal(element, app: app)
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable)
        element.tap()
    }
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
        let app = launch(); prepareSegment(app); cancelReview(app)
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
        let locked = app.staticTexts["merchant.engagement.locked"]
        reveal(locked, app: app, towardTop: true)
        XCTAssertTrue(locked.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["merchant.engagement.confirm"].exists)
    }
    func testCampaignCreationExplainsSeparateDispatch() {
        let app = launch(); tap("merchant.engagement.createCampaign",app:app)
        let title = app.textFields["merchant.engagement.editor.title"]; XCTAssertTrue(title.waitForExistence(timeout:5)); title.tap(); title.typeText("Example title")
        let content = app.descendants(matching:.any)["merchant.engagement.editor.content"]; content.tap(); content.typeText("Example message")
        tap("merchant.engagement.editor.review",app:app)
        XCTAssertTrue(app.descendants(matching:.any)["merchant.engagement.audience"].waitForExistence(timeout:5))
        tap("merchant.engagement.confirm",app:app)
        let receipt = app.staticTexts["The task was created. Dispatch requires its own review."]
        reveal(receipt, app: app)
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
    }
    func testOrdinaryHTTPProductionFactoryReviewUsesExplicitConfirmation() {
        let app = launch("productionFactory"); prepareSegment(app)
        let confirm = app.buttons["merchant.engagement.confirm"]
        reveal(confirm, app: app)
        XCTAssertEqual(confirm.label, "Confirm reviewed action")
        confirm.tap()
        let receipt = app.staticTexts["The segment-save response was received."]
        reveal(receipt, app: app)
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
    }
    func testChineseOrdinaryHTTPProductionReviewCanBeCancelled() {
        let app = launch("productionFactory", language: "zh-Hans"); prepareSegment(app)
        let confirm = app.buttons["merchant.engagement.confirm"]
        reveal(confirm, app: app)
        XCTAssertEqual(confirm.label, "确认已审核操作")
        cancelReview(app)
        XCTAssertTrue(app.navigationBars["客户运营"].exists)
        attachFixtureScreenshot(self, app: app, name: "Chinese CRM review canceled without receipt")
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
        // This fixture control is outside the list, above its navigation bar.
        let signOut = app.buttons["merchant.engagement.fixtureSignOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5)); XCTAssertTrue(signOut.isHittable)
        signOut.tap()
        XCTAssertFalse(app.buttons["merchant.engagement.segment.71001"].exists)
        XCTAssertFalse(app.buttons["merchant.engagement.saveSegment"].exists)
        XCTAssertFalse(app.buttons["merchant.engagement.confirm"].exists)
    }
}
