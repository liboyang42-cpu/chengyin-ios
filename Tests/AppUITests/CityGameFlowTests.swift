import XCTest

/// Offline W20 CITY business fixture through the real CityPlayerView. Synthetic data only.
final class CityGameFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ flags: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "cityGame", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + flags
        app.launch(); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        button.tap()
    }
    private func recorder(_ name: String, _ app: XCUIApplication) -> String {
        let text = app.staticTexts["cityGame.recorder." + name]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        return text.label
    }
    private func waitFor(_ element: XCUIElement, _ app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), app.debugDescription)
    }

    func testDisabledSectionStatesNotEnabledAndOffersNoAction() {
        let app = launch(["--city-game-disabled"])
        waitFor(app.descendants(matching: .any)["cityGame.notEnabled"], app)
        XCTAssertFalse(app.buttons["cityGame.roll"].exists)
        XCTAssertFalse(app.buttons["cityGame.action.ACQUIRE_PROPERTY.prop-cafe"].exists)
        XCTAssertEqual(recorder("submissions", app), "0")
    }

    func testCancelledReviewSendsNothingAndConfirmedAcquireAppliesOnce() {
        let app = launch()
        tap("cityGame.action.ACQUIRE_PROPERTY.prop-cafe", app)
        waitFor(app.otherElements["cityGame.review"], app)
        XCTAssertTrue(app.staticTexts["Only you pay. Teammates are never charged, and nothing is deducted if it fails."].exists)
        tap("cityGame.cancel", app)
        XCTAssertFalse(app.otherElements["cityGame.review"].exists)
        XCTAssertEqual(recorder("submissions", app), "0")
        tap("cityGame.action.ACQUIRE_PROPERTY.prop-cafe", app)
        tap("cityGame.confirm", app)
        waitFor(app.staticTexts["cityGame.outcome"], app)
        XCTAssertEqual(recorder("submissions", app), "1"); XCTAssertEqual(recorder("effects", app), "1")
        XCTAssertTrue(app.staticTexts["Operated by your team"].waitForExistence(timeout: 5))
    }

    func testLostResponseIsReadBackWithoutRepeatingTheEffect() {
        let app = launch(["--city-game-lost"])
        tap("cityGame.action.ACCEPT_TASK.prop-park", app)
        tap("cityGame.confirm", app)
        waitFor(app.buttons["cityGame.readBack"], app)
        XCTAssertEqual(recorder("effects", app), "1")
        tap("cityGame.readBack", app)
        waitFor(app.staticTexts["cityGame.outcome"], app)
        XCTAssertEqual(recorder("submissions", app), "1"); XCTAssertEqual(recorder("effects", app), "1")
    }

    func testExactRetryReusesTheSameRequestAndNeverChargesTwice() {
        let app = launch(["--city-game-lost"])
        tap("cityGame.action.ACQUIRE_PROPERTY.prop-cafe", app)
        tap("cityGame.confirm", app)
        tap("cityGame.retry", app)
        waitFor(app.staticTexts["cityGame.outcome"], app)
        XCTAssertEqual(recorder("submissions", app), "2"); XCTAssertEqual(recorder("requestIds", app), "1")
        XCTAssertEqual(recorder("effects", app), "1")
    }

    func testMissingReceiptStaysUnknownUntilTheServerHasIt() {
        let app = launch(["--city-game-lost", "--city-game-receipt-missing"])
        tap("cityGame.action.ACCEPT_TASK.prop-park", app)
        tap("cityGame.confirm", app)
        tap("cityGame.readBack", app)
        waitFor(app.staticTexts["cityGame.notice"], app)
        XCTAssertTrue(app.buttons["cityGame.readBack"].exists)
        tap("cityGame.readBack", app)
        waitFor(app.staticTexts["cityGame.outcome"], app)
        XCTAssertEqual(recorder("effects", app), "1")
    }

    func testChangedQuoteIsNeverAutoAccepted() {
        let app = launch(["--city-game-quote-changed"])
        tap("cityGame.action.ACQUIRE_PROPERTY.prop-cafe", app)
        tap("cityGame.confirm", app)
        waitFor(app.staticTexts["cityGame.outcome"], app)
        XCTAssertTrue(app.staticTexts["The price changed. Nothing was charged; request a new quote to continue."].exists)
        XCTAssertEqual(recorder("submissions", app), "1"); XCTAssertEqual(recorder("effects", app), "0")
        XCTAssertFalse(app.otherElements["cityGame.review"].exists)
    }

    func testZeroPointsKeepsNeutralGoalsAndBlocksPaidConfirmation() {
        let app = launch(["--city-game-zero-points"])
        waitFor(app.staticTexts["cityGame.zeroPoints"], app)
        XCTAssertTrue(app.buttons["cityGame.action.ACCEPT_TASK.prop-park"].waitForExistence(timeout: 5))
        tap("cityGame.action.ACQUIRE_PROPERTY.prop-cafe", app)
        waitFor(app.staticTexts["cityGame.review.insufficient"], app)
        XCTAssertFalse(app.buttons["cityGame.confirm"].isEnabled)
        XCTAssertEqual(recorder("submissions", app), "0")
    }

    func testFrozenBoardShowsNoticeAndNoActions() {
        let app = launch(["--city-game-frozen"])
        waitFor(app.staticTexts["cityGame.boardNotice"], app)
        XCTAssertFalse(app.buttons["cityGame.roll"].exists)
        XCTAssertFalse(app.buttons["cityGame.action.ACCEPT_TASK.prop-park"].exists)
    }

    func testPausedVenueOffersNoServiceOrChallengeAndUndisclosedFeeIsNotAcceptable() {
        let paused = launch(["--city-game-paused"])
        waitFor(paused.otherElements["cityGame.property.prop-shop"], paused)
        XCTAssertFalse(paused.buttons["cityGame.service.svc-shop-route"].exists)
        XCTAssertFalse(paused.buttons["cityGame.action.START_CHALLENGE.prop-shop"].exists)
        paused.terminate()
        let open = launch()
        waitFor(open.buttons["cityGame.service.svc-shop-route"], open)
        XCTAssertFalse(open.buttons["cityGame.service.svc-shop-pending"].exists)
    }

    func testChineseCopy() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.staticTexts["城市经营"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["cityGame.roll"].waitForExistence(timeout: 5))
    }
}
