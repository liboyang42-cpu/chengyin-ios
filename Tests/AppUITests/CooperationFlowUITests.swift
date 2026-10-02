import XCTest

/// Requires the host app's --cooperation-flow-fixture branch (documented integration step).
final class CooperationFlowUITests: XCTestCase {
    func testSyntheticFinanceAndDormantReview() {
        let app = XCUIApplication()
        app.launchArguments += ["--cooperation-flow-fixture", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.otherElements["coopflow.workbench"].waitForExistence(timeout: 5))
        app.buttons["coopflow.route.coopflow.finance"].tap()
        app.buttons["coopflow.settlement.finance.8"].tap()
        XCTAssertTrue(app.staticTexts["Amount not confirmed"].exists)
        XCTAssertTrue(app.staticTexts["Pending settlement"].exists)
    }
    func testTemplatePreviewCannotSubmit() {
        let app = XCUIApplication()
        app.launchArguments += ["--cooperation-flow-fixture", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["coopflow.route.coopflow.templates"].tap()
        app.buttons["coopflow.row.0"].tap()
        app.buttons["Review template deletion"].tap()
        XCTAssertTrue(app.buttons["coopflow.submit.disabled"].exists)
        XCTAssertFalse(app.buttons["coopflow.submit.disabled"].isEnabled)
    }

    private func launch(language: String = "en", denied: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--cooperation-flow-fixture", "-AppleLanguages", "(\(language))",
                                "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if denied { app.launchArguments += ["--cooperation-flow-denied"] }
        app.launch(); return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
    func testNormalNearbyEntryExplainsUnavailableLocationWithoutPermissionPrompt() {
        for language in ["en", "zh-Hans"] {
            let app = launch(language: language)
            let entry = app.buttons["coopflow.route.coopflow.nearby"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
            XCTAssertTrue(app.staticTexts[language == "en" ? "Nearby search and its location provider are not enabled in this build." : "当前版本尚未启用附近商家查询和定位服务。"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(entry.exists)
            app.terminate()
        }
    }
    func testReceivedApplicationOpensDraftAndReviewBackPreservesText() {
        let app = launch()
        let applications = app.buttons["coopflow.route.coopflow.receivedApplications"]
        reveal(applications, app: app); applications.tap()
        XCTAssertTrue(app.buttons["coopflow.row.0"].waitForExistence(timeout: 5))
        app.buttons["coopflow.row.0"].tap()
        let reply = app.buttons["coopflow.invite.reply"]
        reveal(reply, app: app); reply.tap()
        let message = app.textFields["coopflow.invite.message"]
        let multiline = app.textViews["coopflow.invite.message"]
        let field = message.waitForExistence(timeout: 2) ? message : multiline
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Keep this local draft")
        app.buttons["Done"].tap()
        app.buttons["coopflow.invite.review"].tap()
        let submit = app.buttons["coopflow.submit.disabled"]
        reveal(submit, app: app)
        XCTAssertTrue(submit.exists); XCTAssertFalse(submit.isEnabled)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(field.value as? String, "Keep this local draft")
        app.buttons["coopflow.invite.cancel"].tap()
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
        let applications = app.buttons["coopflow.route.coopflow.receivedApplications"]
        reveal(applications, app: app); applications.tap()
        XCTAssertTrue(app.staticTexts["coopflow.issue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coopflow.invite.reply"].exists)
    }
    func testSessionChangeDropsNavigationAndReceivedApplicationData() {
        let app = launch()
        let applications = app.buttons["coopflow.route.coopflow.receivedApplications"]
        reveal(applications, app: app); applications.tap()
        XCTAssertTrue(app.buttons["coopflow.row.0"].waitForExistence(timeout: 5))
        app.buttons["coopflow.fixture.signOut"].tap()
        XCTAssertFalse(app.buttons["coopflow.row.0"].exists)
        reveal(applications, app: app); applications.tap()
        XCTAssertTrue(app.staticTexts["Sign in to view your cooperation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["coopflow.invite.reply"].exists)
    }
}
