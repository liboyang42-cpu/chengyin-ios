import XCTest

/// Offline fixtures exercise the real presentation views. All Apple execution is NOT_RUN locally.
final class NativePresentationPatternFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String, language: String = "en", maximum: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN", "--uitesting-module", "presentationPatterns", "--uitesting-presentation-scenario", scenario]
        if maximum { app.launchArguments += ["--uitesting-max-text", "--uitesting-dark", "--uitesting-reduce-motion"] }
        app.launch()
        if maximum { assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility5") }
    }
    private func wait(_ element: XCUIElement, _ predicate: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        for _ in 0..<8 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.isHittable, app.debugDescription, file: file, line: line)
        button.tap()
    }
    func testGalleryEnglishPagesClosesAndReopensAtSelectedImage() {
        launch("gallery"); tap("media.gallery.open.0")
        let position = app.staticTexts["media.gallery.position"]
        wait(position, "label == '1 / 2'")
        XCTAssertFalse(app.buttons["media.gallery.previous"].isEnabled)
        tap("media.gallery.next"); wait(position, "label == '2 / 2'")
        XCTAssertFalse(app.buttons["media.gallery.next"].isEnabled)
        tap("media.gallery.close"); wait(app.buttons["media.gallery.close"], "exists == false")
        tap("media.gallery.open.0"); wait(position, "label == '1 / 2'")
        attachFixtureScreenshot(self, app: app, name: "Media fullscreen English light reopened")
    }
    func testGalleryChineseMaximumTextDarkReducedMotionKeepsPagingAndClose() {
        launch("gallery", language: "zh-Hans", maximum: true)
        tap("media.gallery.open.0"); wait(app.staticTexts["media.gallery.position"], "label == '1 / 2'")
        tap("media.gallery.next"); wait(app.staticTexts["media.gallery.position"], "label == '2 / 2'")
        attachFixtureScreenshot(self, app: app, name: "Media fullscreen Chinese accessibility5 dark reduced-motion")
        tap("media.gallery.close"); wait(app.buttons["media.gallery.close"], "exists == false")
        XCTAssertTrue(app.buttons["media.gallery.open.0"].isHittable)
    }
    func testMalformedImageFinishesWithRetryAndClose() {
        launch("galleryRetry"); tap("presentation.fixture.openFailure")
        XCTAssertTrue(app.buttons["media.gallery.retry"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["media.gallery.close"].isHittable)
        tap("media.gallery.retry")
        wait(app.buttons["media.gallery.retry"], "exists == false")
        wait(app.activityIndicators.firstMatch, "exists == false")
        tap("media.gallery.close")
        wait(app.buttons["presentation.fixture.openFailure"], "hittable == true")
    }
    func testGalleryScopeChangeDismissesWithoutStaleReopen() {
        launch("gallery")
        // Let thumbnails finish before arming the next full-screen image task.
        wait(app.staticTexts["presentation.fixture.readCount"], "label == '2'")
        tap("presentation.fixture.expire"); tap("media.gallery.open.0")
        XCTAssertTrue(app.staticTexts["presentation.fixture.expired"].waitForExistence(timeout: 10), app.debugDescription)
        wait(app.buttons["media.gallery.close"], "exists == false")
        tap("media.gallery.open.0")
        XCTAssertTrue(app.buttons["media.gallery.close"].waitForExistence(timeout: 10))
        tap("media.gallery.close")
    }
    func testDisabledMediaAndCameraEntrypointsDoNotSpinOrRequestPermission() {
        launch("galleryDisabled"); tap("media.gallery.open.0")
        XCTAssertTrue(app.buttons["media.gallery.close"].waitForExistence(timeout: 10))
        wait(app.activityIndicators.firstMatch, "exists == false")
        XCTAssertFalse(app.buttons["media.gallery.retry"].exists)
        app.terminate()
        for scenario in ["stampDisabled", "posterDisabled"] {
            launch(scenario)
            let id = scenario == "stampDisabled" ? "media.stamp.capture" : "media.poster.scan"
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons[id].isEnabled)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            wait(app.activityIndicators.firstMatch, "exists == false")
            app.terminate()
        }
    }
    func testParticipationSupportStaysInSheetAndReturnsBeforeClose() {
        launch("journey"); tap("playerJourney.participation.71"); tap("playerJourney.support")
        XCTAssertTrue(app.descendants(matching: .any)["participationSupport.notConfigured"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["presentation.fixture.routed"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["playerJourney.detail.close"].waitForExistence(timeout: 10))
        tap("playerJourney.detail.close")
        wait(app.buttons["playerJourney.participation.71"], "hittable == true")
        tap("playerJourney.participation.71")
        XCTAssertTrue(app.buttons["playerJourney.support"].waitForExistence(timeout: 10))
    }
    func testParticipationPlayWaitsForSheetDismissal() {
        launch("journey"); tap("playerJourney.participation.71"); tap("playerJourney.start")
        XCTAssertTrue(app.staticTexts["presentation.fixture.routed"].waitForExistence(timeout: 10))
        wait(app.buttons["playerJourney.detail.close"], "exists == false")
        tap("playerJourney.participation.71")
        XCTAssertTrue(app.buttons["playerJourney.detail.close"].waitForExistence(timeout: 10))
    }
    func testParticipationFailureRetriesAndScopeExpiryDismisses() {
        launch("journeyFailure")
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10)); retry.tap()
        XCTAssertTrue(app.buttons["playerJourney.participation.71"].waitForExistence(timeout: 10))
        app.terminate(); launch("journeyScope"); tap("playerJourney.participation.71")
        XCTAssertTrue(app.staticTexts["presentation.fixture.expired"].waitForExistence(timeout: 10))
        wait(app.buttons["playerJourney.detail.close"], "exists == false")
        XCTAssertFalse(app.staticTexts["presentation.fixture.routed"].exists)
        tap("playerJourney.participation.71")
        XCTAssertTrue(app.buttons["playerJourney.detail.close"].waitForExistence(timeout: 10))
    }
}
