import XCTest

/// Offline W19 "I'm back" fixture on the real private-home page. Synthetic data only;
/// no location provider is started and the home point is never displayed.
final class HomeReturnFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ flags: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "homeReturn", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : "zh_CN"] + flags
        app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let value = app.descendants(matching: .any)[id]
        XCTAssertTrue(revealFixtureElement(value, in: app, requiresHittable: false), app.debugDescription)
        XCTAssertTrue(value.waitForExistence(timeout: 8), app.debugDescription)
        return value
    }
    /// LabeledContent may expose its value as label or value depending on the OS release.
    private func text(_ id: String, _ app: XCUIApplication) -> String {
        let value = element(id, app)
        return value.label + " " + ((value.value as? String) ?? "")
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        XCTAssertTrue(button.waitForExistence(timeout: 8)); button.tap()
    }
    private func recorder(_ name: String, _ app: XCUIApplication) -> String {
        let text = app.staticTexts["homeReturn.recorder." + name]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        return text.label
    }

    func testDisabledCapabilityShowsNotEnabledAndNoCheckIn() {
        let app = launch(["--home-return-disabled"])
        XCTAssertTrue(element("homeReturn.phase", app).label.contains("Not enabled"))
        XCTAssertFalse(app.buttons["homeReturn.checkIn"].exists)
        XCTAssertEqual(recorder("restores", app), "0")
    }

    func testCheckInRestoresOnceToServerMaximum() {
        let app = launch()
        XCTAssertTrue(text("homeReturn.account", app).contains("2 / 5"))
        tap("homeReturn.checkIn", app)
        _ = element("homeReturn.decision", app)
        XCTAssertTrue(text("homeReturn.account", app).contains("5 / 5"))
        XCTAssertEqual(recorder("restores", app), "1"); XCTAssertEqual(recorder("effects", app), "1")
    }

    func testDeniedLocationAndLowAccuracyGiveDistinctFailuresWithoutRestore() {
        let denied = launch(["--home-return-denied"])
        tap("homeReturn.checkIn", denied)
        XCTAssertTrue(element("homeReturn.failure", denied).label.contains("permission"))
        XCTAssertEqual(recorder("restores", denied), "0")
        denied.terminate()
        let weak = launch(["--home-return-low-accuracy"])
        tap("homeReturn.checkIn", weak)
        XCTAssertTrue(element("homeReturn.failure", weak).label.contains("accuracy"))
        XCTAssertEqual(recorder("restores", weak), "0")
    }

    func testServerDecisionsOutOfRadiusAndCooldownAreNotFakedAsSuccess() {
        let far = launch(["--home-return-out-of-radius"])
        tap("homeReturn.checkIn", far)
        XCTAssertTrue(element("homeReturn.failure", far).label.contains("not at your home"))
        XCTAssertEqual(recorder("restores", far), "0")
        far.terminate()
        let cooling = launch(["--home-return-cooldown"])
        tap("homeReturn.checkIn", cooling)
        XCTAssertTrue(element("homeReturn.failure", cooling).label.contains("cooling down"))
        XCTAssertEqual(recorder("restores", cooling), "0")
    }

    func testLostRestoreIsReadBackAndExactRetryNeverRestoresTwice() {
        let app = launch(["--home-return-lost"])
        tap("homeReturn.checkIn", app)
        tap("homeReturn.retry", app)
        _ = element("homeReturn.decision", app)
        XCTAssertEqual(recorder("restores", app), "2"); XCTAssertEqual(recorder("effects", app), "1")
    }

    func testNoHomeAsksToSetHomeFirst() {
        let app = launch(["--home-return-no-home"])
        _ = element("homeReturn.needHome", app)
        XCTAssertFalse(app.buttons["homeReturn.checkIn"].exists)
    }

    func testChineseCopy() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.buttons["homeReturn.checkIn"].waitForExistence(timeout: 8) || revealFixtureElement(app.buttons["homeReturn.checkIn"], in: app))
        XCTAssertTrue(app.buttons["我回来了"].exists)
    }
}
