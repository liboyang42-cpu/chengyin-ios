import XCTest

final class PrivateHomeMapPickerFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(fixture: Bool = true, language: String = "en", maximum: Bool = false, lost: Bool = false, accountRoute: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); runningApp = app
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "privateHome", "--private-home-map-recorder", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        if fixture { app.launchArguments.append("--private-home-map-fixture") }
        if maximum { app.launchArguments += ["--uitesting-max-text", "--uitesting-dark", "--uitesting-reduce-motion"] }
        if lost { app.launchArguments.append("--private-home-lost") }
        if accountRoute { app.launchArguments.append("--private-home-account-route") }
        app.launch()
        if accountRoute { tap("account.privateHome", app) }
        return app
    }
    private func fixedRecorderControlIsReady(_ id: String, _ app: XCUIApplication) -> Bool {
        guard ["privateHome.fixture.replaceOwner", "privateHome.fixture.revokeSource"].contains(id) else { return false }
        let button = app.buttons[id]
        guard button.exists, button.isEnabled, button.isHittable,
              !button.frame.isEmpty, app.frame.contains(button.frame) else { return false }
        return !app.keyboards.allElementsBoundByIndex.contains { $0.frame.intersects(button.frame) }
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]
        if ["privateHome.fixture.replaceOwner", "privateHome.fixture.revokeSource"].contains(id) {
            XCTAssertTrue(fixedRecorderControlIsReady(id, app), app.debugDescription)
        } else {
            XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        }
        XCTAssertTrue(button.isEnabled); button.tap()
    }
    private func assertRecorderLeavesFormGestureClear(_ app: XCUIApplication) {
        let recorder = app.descendants(matching: .any)["privateHome.fixture.recorder"].firstMatch
        XCTAssertTrue(recorder.waitForExistence(timeout: 5))
        XCTAssertFalse(recorder.frame.isEmpty)
        XCTAssertTrue(app.frame.contains(recorder.frame))
        XCTAssertLessThan(recorder.frame.height, app.frame.height * 0.25)
        let contentTop = app.navigationBars.firstMatch.frame.maxY + 4
        // This is the unchanged revealFixtureElement downward-gesture start.
        let gestureStart = contentTop + (app.frame.maxY - 40 - contentTop) * 0.75
        XCTAssertGreaterThan(recorder.frame.minY, gestureStart)
        XCTAssertFalse(fixedRecorderControlIsReady("privateHome.map.open", app))
        XCTAssertTrue(fixedRecorderControlIsReady("privateHome.fixture.revokeSource", app))
    }
    private func fill(_ id: String, _ value: String, _ app: XCUIApplication) {
        let field = app.textFields[id]; XCTAssertTrue(revealFixtureElement(field, in: app)); field.tap(); field.typeText(value)
    }
    private func record(_ id: String, _ value: String, _ app: XCUIApplication) {
        let field = app.staticTexts["privateHome.recorder.\(id)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertEqual(field.label, value)
    }
    private func selectValidAndReview(_ app: XCUIApplication) {
        tap("privateHome.map.open", app); tap("privateHome.map.fixture.valid", app)
        let coordinates = app.staticTexts["privateHome.coordinateReview"]
        XCTAssertTrue(revealFixtureElement(coordinates, in: app)); XCTAssertEqual(coordinates.label, "12.345678, 45.678901 · WGS84")
        fill("privateHome.map.label", "Synthetic home", app); tap("privateHome.map.review", app)
        XCTAssertTrue(app.buttons["privateHome.confirm"].waitForExistence(timeout: 5))
        record("requests", "0", app)
    }
    func testInactiveProviderExplainsGateAndManualEntryStillReviews() {
        let app = launch(fixture: false); record("starts", "0", app)
        tap("privateHome.map.open", app)
        XCTAssertTrue(app.staticTexts["privateHome.map.issue"].waitForExistence(timeout: 5))
        XCTAssertTrue(revealFixtureElement(app.buttons["privateHome.map.review"], in: app))
        XCTAssertFalse(app.buttons["privateHome.map.review"].isEnabled); XCTAssertEqual(app.maps.count, 0); XCTAssertEqual(app.alerts.count, 0)
        tap("privateHome.map.manual", app); record("starts", "0", app); record("requests", "0", app)
        fill("privateHome.label", "Manual point", app); fill("privateHome.latitude", "12.345678", app); fill("privateHome.longitude", "45.678901", app)
        tap("privateHome.reviewSet", app); XCTAssertTrue(app.buttons["privateHome.confirm"].waitForExistence(timeout: 5)); record("requests", "0", app)
    }
    func testSelectionReviewAndConfirmUseExactPointThroughOwnerRecorder() {
        let app = launch(); record("starts", "0", app); selectValidAndReview(app)
        tap("privateHome.confirm", app); XCTAssertTrue(app.staticTexts["Private home saved"].waitForExistence(timeout: 5))
        record("requests", "1", app); record("receipts", "1", app); record("exactPoint", "true", app)
        XCTAssertEqual(app.alerts.count, 0); XCTAssertEqual(app.maps.count, 0)
    }
    func testCancelReopenHasNoSelectedPointAndReviewCancelNeverSaves() {
        let app = launch(); tap("privateHome.map.open", app); tap("privateHome.map.fixture.valid", app)
        fill("privateHome.map.label", "Discarded label", app); tap("privateHome.map.cancel", app)
        record("requests", "0", app); tap("privateHome.map.open", app)
        XCTAssertTrue(revealFixtureElement(app.buttons["privateHome.map.review"], in: app)); XCTAssertFalse(app.buttons["privateHome.map.review"].isEnabled)
        XCTAssertFalse(app.staticTexts["privateHome.coordinateReview"].exists)
        tap("privateHome.map.fixture.valid", app)
        XCTAssertTrue(revealFixtureElement(app.textFields["privateHome.map.label"], in: app))
        XCTAssertEqual(app.textFields["privateHome.map.label"].value as? String, "Private label")
        tap("privateHome.map.cancel", app)
        selectValidAndReview(app); tap("privateHome.cancel", app); record("requests", "0", app)
        XCTAssertFalse(app.buttons["privateHome.confirm"].exists)
    }
    func testUnknownDatumPrecisionAndRangeClearPreviouslyValidPreview() {
        let app = launch(); tap("privateHome.map.open", app)
        for choice in ["unknown", "gcj02", "precision", "outOfRange"] {
            tap("privateHome.map.fixture.valid", app); tap("privateHome.map.fixture.\(choice)", app)
            XCTAssertTrue(revealFixtureElement(app.buttons["privateHome.map.review"], in: app)); XCTAssertFalse(app.buttons["privateHome.map.review"].isEnabled)
            XCTAssertFalse(app.staticTexts["privateHome.coordinateReview"].exists)
        }
        tap("privateHome.map.cancel", app); record("requests", "0", app)
    }
    func testSessionInvalidationDismissesSelectionWithoutSave() {
        let app = launch(); tap("privateHome.map.open", app); tap("privateHome.map.fixture.valid", app); tap("privateHome.map.fixture.invalidate", app)
        XCTAssertTrue(app.staticTexts["Session ended"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["privateHome.map.open"].exists)
        XCTAssertFalse(app.buttons["privateHome.confirm"].exists); record("requests", "0", app)
    }
    func testLostMapSaveRequiresExactRetryAndNoNewSelection() {
        let app = launch(lost: true); selectValidAndReview(app); tap("privateHome.confirm", app)
        XCTAssertTrue(app.buttons["privateHome.retry"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["privateHome.map.open"].exists)
        record("requests", "1", app); tap("privateHome.retry", app)
        XCTAssertTrue(app.staticTexts["Private home saved"].waitForExistence(timeout: 5)); record("requests", "2", app); record("receipts", "1", app); record("exactPoint", "true", app)
    }
    func testBothLanguagesMaximumTextKeepPreviewAndCancellationReachable() {
        for language in ["en", "zh-Hans"] {
            let app = launch(language: language, maximum: true)
            assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility5")
            assertRecorderLeavesFormGestureClear(app)
            tap("privateHome.map.open", app); tap("privateHome.map.fixture.valid", app)
            XCTAssertTrue(revealFixtureElement(app.staticTexts["privateHome.coordinateReview"], in: app))
            attachFixtureScreenshot(self, app: app, name: "Private game-home synthetic point \(language) maximum text")
            tap("privateHome.map.cancel", app); record("requests", "0", app)
            XCTAssertEqual(app.alerts.count, 0); app.terminate()
        }
    }
    func testSameAccountRouteReplacementClearsManualFields() {
        let app = launch(accountRoute: true)
        fill("privateHome.label", "Old private label", app)
        fill("privateHome.latitude", "12.345678", app); fill("privateHome.longitude", "45.678901", app)
        tap("privateHome.fixture.replaceOwner", app); record("replacements", "1", app)
        for (id, placeholder) in [("label", "Private label"), ("latitude", "Latitude"), ("longitude", "Longitude")] {
            let field = app.textFields["privateHome.\(id)"]
            XCTAssertTrue(revealFixtureElement(field, in: app)); XCTAssertEqual(field.value as? String, placeholder)
        }
        tap("privateHome.reviewSet", app)
        XCTAssertFalse(app.buttons["privateHome.confirm"].exists); record("requests", "0", app)
        tap("privateHome.map.open", app); tap("privateHome.map.manual", app)
        XCTAssertTrue(app.textFields["privateHome.label"].exists)
    }
    func testSameAccountRouteReplacementDiscardsPickerAndLateCallback() {
        let app = launch(accountRoute: true)
        tap("privateHome.map.open", app); tap("privateHome.map.fixture.valid", app)
        fill("privateHome.map.label", "Old picker label", app)
        tap("privateHome.map.fixture.replaceOwner", app); record("replacements", "1", app)
        XCTAssertFalse(app.staticTexts["privateHome.coordinateReview"].exists)
        tap("privateHome.map.open", app); tap("privateHome.map.fixture.late", app)
        XCTAssertTrue(revealFixtureElement(app.buttons["privateHome.map.review"], in: app))
        XCTAssertFalse(app.buttons["privateHome.map.review"].isEnabled)
        XCTAssertFalse(app.staticTexts["privateHome.coordinateReview"].exists)
        tap("privateHome.map.fixture.valid", app)
        XCTAssertTrue(revealFixtureElement(app.textFields["privateHome.map.label"], in: app))
        XCTAssertEqual(app.textFields["privateHome.map.label"].value as? String, "Private label")
        tap("privateHome.map.cancel", app); record("requests", "0", app)
        tap("privateHome.map.open", app)
        XCTAssertTrue(revealFixtureElement(app.buttons["privateHome.map.review"], in: app))
        XCTAssertFalse(app.buttons["privateHome.map.review"].isEnabled)
        tap("privateHome.map.cancel", app); record("requests", "0", app)
    }
    func testSourceRevocationAfterReviewBlocksFinalConfirmation() {
        let app = launch(accountRoute: true); selectValidAndReview(app)
        tap("privateHome.fixture.revokeSource", app); tap("privateHome.confirm", app)
        XCTAssertTrue(app.staticTexts["privateHome.map.confirmationIssue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["privateHome.confirm"].exists)
        XCTAssertFalse(app.staticTexts["privateHome.coordinateReview"].exists)
        record("requests", "0", app); record("receipts", "0", app)
    }
}
