import XCTest

/// Offline DEBUG fixture only (`--uitesting-module square --uitesting-square-scenario mediaChain`).
/// Synthetic inspections; no file, network, upload or playback request is made.
final class SquarePostMediaChainFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch() {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "--uitesting-module", "square", "--uitesting-square-scenario", "mediaChain"]
        app.launch()
    }
    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.buttons[id]
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription, file: file, line: line)
        element.tap()
    }
    private func exists(_ id: String) -> Bool { app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: 5) }

    func testCheckedVideoKeepsUploadDisabledAndExplainsWhy() {
        launch()
        tap("square.video.fixture.valid")
        XCTAssertTrue(exists("square.video.preview"))
        XCTAssertTrue(exists("square.video.accepted"))
        let upload = app.buttons["square.video.upload"]
        XCTAssertTrue(upload.exists); XCTAssertFalse(upload.isEnabled)
        XCTAssertTrue(exists("square.video.uploadBlocked"))
    }

    func testOverLongVideoIsRejectedAndRemovable() {
        launch()
        tap("square.video.fixture.long")
        XCTAssertTrue(exists("square.video.reject"))
        XCTAssertFalse(app.descendants(matching: .any)["square.video.accepted"].exists)
        tap("square.video.remove")
        XCTAssertFalse(app.descendants(matching: .any)["square.video.preview"].exists)
    }

    func testSavedDraftRestoresAndDetectsLostLocalFile() {
        launch()
        tap("square.video.fixture.valid")
        tap("square.video.fixture.save")
        tap("square.video.remove")
        tap("square.video.fixture.restore")
        XCTAssertTrue(app.staticTexts["Restored from your draft"].waitForExistence(timeout: 5))
        tap("square.video.fixture.loseFile")
        tap("square.video.fixture.restore")
        XCTAssertTrue(app.staticTexts["The local video file is gone. Choose it again."].waitForExistence(timeout: 5))
    }

    func testReadPathOffersExplicitPlayAndShowsReviewState() {
        launch()
        let play = app.buttons["square.video.play.51"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(revealFixtureElement(play, in: app))
        XCTAssertFalse(app.descendants(matching: .any)["square.video.player.51"].exists)
        XCTAssertTrue(app.staticTexts["Video in review"].exists || revealFixtureElement(app.staticTexts["Video in review"], in: app))
    }
}
