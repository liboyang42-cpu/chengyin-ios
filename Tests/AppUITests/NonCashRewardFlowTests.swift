import XCTest

/// Actual account navigation; normal synthetic integration transport, never live reward APIs.
@MainActor final class NonCashRewardFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { super.setUp(); continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func tap(_ id: String) {
        let element = app.buttons[id]
        if id == "rewards.close" {
            let close = app.navigationBars.buttons[id]
            XCTAssertTrue(close.exists); XCTAssertTrue(close.isEnabled)
            XCTAssertTrue(close.isHittable); close.tap(); return
        }
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription); element.tap()
    }
    private func launch(_ scenario: String? = "content") {
        app.launchArguments = ["--uitesting-integrated-native", "ready", "--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let scenario { app.launchArguments += ["--uitesting-rewards-scenario", scenario] }
        app.launch()
        tap("welcome.player"); tap("auth.otherChannels")
        app.textFields["auth.channels.phone"].tap(); app.textFields["auth.channels.phone"].typeText("10000000000")
        tap("auth.channels.sendCode")
        XCTAssertTrue(app.staticTexts["Code sent. Check your messages."].waitForExistence(timeout: 5))
        app.textFields["auth.channels.code"].tap(); app.textFields["auth.channels.code"].typeText("123456")
        tap("auth.channels.phoneSignIn")
        let account = app.tabBars.buttons["Account"]
        XCTAssertTrue(account.waitForExistence(timeout: 10)); account.tap()
        tap("rewards.open")
    }
    /// Full-method conservative estimate: 480 seconds, unmeasured after source reconstruction.
    func testDetailDisclosesFrozenTermsExactMapOriginAndUnavailableClaimFacts() {
        launch(); tap("rewards.row.example-0")
        XCTAssertTrue(revealFixtureElement(app.staticTexts["rewards.read.frozenTerms"], in: app, requiresHittable: false))
        XCTAssertTrue(revealFixtureElement(app.staticTexts["rewards.read.sourceHint"], in: app, requiresHittable: false))
        XCTAssertEqual(app.staticTexts["rewards.read.contextId.value"].label, "example-map")
        XCTAssertEqual(app.staticTexts["rewards.read.instanceId.value"].label, "example-season")
        XCTAssertTrue(revealFixtureElement(app.staticTexts["rewards.read.qualificationHint"], in: app, requiresHittable: false))
        for id in ["rewards.read.eligibility.value", "rewards.read.claimProgress.value", "rewards.read.allocation.value"] {
            let query = app.staticTexts.matching(identifier: id)
            XCTAssertEqual(query.count, 1)
            XCTAssertEqual(query.element.label, "Not provided by this read contract")
        }
        XCTAssertFalse(app.buttons["Claim reward"].exists)
        attachFixtureScreenshot(self, app: app, name: "Synthetic frozen reward terms and unavailable claim facts")
    }
    func testNormalAccountRewardDetailCloseReopenAndBack() {
        launch(); tap("rewards.row.example-0"); tap("rewards.present")
        XCTAssertTrue(app.descendants(matching: .any)["rewards.presentation"].firstMatch.waitForExistence(timeout: 5))
        tap("rewards.close"); tap("rewards.present"); tap("rewards.close")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["rewards.row.example-0"].waitForExistence(timeout: 5))
        attachFixtureScreenshot(self, app: app, name: "Synthetic My Rewards normal account journey")
    }
    func testPreviewBackgroundDismissesAndCanReopen() {
        launch(); tap("rewards.row.example-0"); tap("rewards.present")
        XCTAssertTrue(app.descendants(matching: .any)["rewards.presentation"].firstMatch.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertFalse(app.buttons["rewards.close"].exists)
        tap("rewards.present")
        XCTAssertTrue(app.descendants(matching: .any)["rewards.presentation"].firstMatch.waitForExistence(timeout: 5))
        tap("rewards.close")
    }
    func testTerminalAwardHasNoPresentationAction() {
        launch(); tap("rewards.row.example-1")
        let unavailable = app.staticTexts["rewards.notPresentable"]
        XCTAssertTrue(revealFixtureElement(unavailable, in: app))
        XCTAssertFalse(app.buttons["rewards.present"].exists)
    }
    func testFailureRetryThenShowsSyntheticRows() {
        launch("failure"); tap("rewards.retry")
        XCTAssertTrue(app.buttons["rewards.row.example-0"].waitForExistence(timeout: 5))
    }
    func testWithoutOptInNoExampleOrRedemptionAppears() {
        launch(nil)
        XCTAssertTrue(app.staticTexts.matching(identifier: "rewards.unavailable").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["rewards.row.example-0"].exists)
        XCTAssertFalse(app.buttons["rewards.present"].exists)
    }
}
