import XCTest

/// Requires the host app's --cooperation-flow-fixture branch (documented integration step).
final class CooperationFlowUITests: XCTestCase {
    func testSyntheticFinanceAndDormantReview() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["coopflow.workbench"].waitForExistence(timeout: 5))
        app.buttons["coopflow.route.coopflow.finance"].tap()
        let settlement = app.buttons["coopflow.settlement.finance.8"]
        XCTAssertTrue(settlement.waitForExistence(timeout: 5)); settlement.tap()
        XCTAssertTrue(app.navigationBars["Settlement details"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Amount not confirmed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pending settlement"].exists)
    }
    func testTemplatePreviewCannotSubmit() {
        let app = launch()
        app.buttons["coopflow.route.coopflow.templates"].tap()
        app.buttons["coopflow.row.0"].tap()
        let deletion = app.buttons["Review template deletion"]
        reveal(deletion, app: app); deletion.tap()
        XCTAssertTrue(app.buttons["coopflow.submit.disabled"].exists)
        XCTAssertFalse(app.buttons["coopflow.submit.disabled"].isEnabled)
    }

    private func launch(language: String = "en", denied: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting-reset-language", "--cooperation-flow-fixture", "-AppleLanguages", "(\(language))",
                                "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if denied { app.launchArguments += ["--cooperation-flow-denied"] }
        app.launch()
        let title = language == "en" ? "Cooperation center" : "合作中心"
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), app.debugDescription)
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription)
    }
    private func openReceivedApplications(_ app: XCUIApplication) {
        let entry = app.buttons["coopflow.route.coopflow.receivedApplications"]
        reveal(entry, app: app); entry.tap()
        XCTAssertTrue(app.navigationBars["Received club applications"].waitForExistence(timeout: 5), app.debugDescription)
    }
    func testNormalNearbyEntryExplainsUnavailableLocationWithoutPermissionPrompt() {
        for language in ["en", "zh-Hans"] {
            let app = launch(language: language)
            let entry = app.buttons["coopflow.route.coopflow.nearby"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
            XCTAssertTrue(app.staticTexts[language == "en" ? "Nearby search and its location provider are not enabled in this build." : "当前版本尚未启用附近商家查询和定位服务。"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            attachFixtureScreenshot(self, app: app, name: "Nearby purpose gate \(language)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(entry.exists)
            app.terminate()
        }
    }
    func testReceivedApplicationOpensDraftAndReviewBackPreservesText() {
        let app = launch()
        openReceivedApplications(app)
        XCTAssertTrue(app.buttons["coopflow.row.0"].waitForExistence(timeout: 5))
        app.buttons["coopflow.row.0"].tap()
        let reply = app.buttons["coopflow.invite.reply"]
        reveal(reply, app: app); reply.tap()
        let message = app.textFields["coopflow.invite.message"]
        let multiline = app.textViews["coopflow.invite.message"]
        let field = message.waitForExistence(timeout: 2) ? message : multiline
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Keep this local draft")
        app.buttons["Done"].tap()
        attachFixtureScreenshot(self, app: app, name: "Cooperation invitation composer after keyboard dismissal")
        app.buttons["coopflow.invite.review"].tap()
        let submit = app.buttons["coopflow.submit.disabled"]
        XCTAssertTrue(revealFixtureElement(submit, in: app, requiresHittable: false))
        XCTAssertTrue(submit.exists); XCTAssertFalse(submit.isEnabled)
        attachFixtureScreenshot(self, app: app, name: "Cooperation invitation local review")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(field.value as? String, "Keep this local draft")
        app.buttons["coopflow.invite.cancel"].tap()
        attachFixtureScreenshot(self, app: app, name: "Cooperation unsaved draft discard decision")
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(field.value as? String, "Keep this local draft")
        app.buttons["coopflow.invite.cancel"].tap()
        app.buttons["Discard draft"].tap()
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertNotEqual(field.value as? String, "Keep this local draft")
        app.buttons["coopflow.invite.cancel"].tap()
        XCTAssertTrue(reply.exists)
    }
    func testDeniedReceivedApplicationsHaveNoInvitationReview() {
        let app = launch(denied: true)
        openReceivedApplications(app)
        XCTAssertTrue(app.staticTexts["coopflow.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coopflow.invite.reply"].exists)
    }
    func testSessionChangeDropsNavigationAndReceivedApplicationData() {
        let app = launch()
        openReceivedApplications(app)
        XCTAssertTrue(app.buttons["coopflow.row.0"].waitForExistence(timeout: 5))
        // Fixture-level control stays visible while the read destination is pushed.
        let signOut = app.buttons["coopflow.fixture.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5)); XCTAssertTrue(signOut.isHittable)
        signOut.tap()
        XCTAssertTrue(app.navigationBars["Cooperation center"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["coopflow.row.0"].exists)
        openReceivedApplications(app)
        XCTAssertTrue(app.staticTexts["Sign in to view your cooperation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coopflow.invite.reply"].exists)
    }
}
