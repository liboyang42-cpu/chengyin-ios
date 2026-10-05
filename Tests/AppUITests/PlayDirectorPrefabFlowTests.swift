import XCTest

final class PlayDirectorPrefabFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil }
    private func launch(_ module: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", module, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        runningApp = app; app.launch(); return app
    }
    func testDirectorOnlyShowsSourceAllowedActions() {
        let app = launch("playDirector")
        XCTAssertTrue(app.buttons["playx.director.action.FINISH"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["playx.director.action.START"].exists)
        XCTAssertFalse(app.buttons["playx.director.action.PREPARE"].exists)
    }
    func testDirectorBroadcastReviewCanBeCancelled() {
        let app = launch("playDirector")
        let button = app.buttons["playx.director.action.BROADCAST"]
        XCTAssertTrue(revealFixtureElement(button, in: app), app.debugDescription)
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        XCTAssertTrue(app.navigationBars["Activity director"].waitForExistence(timeout: 3))
        let cancel = app.buttons["playx.director.cancelEditor"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription); cancel.tap()
        XCTAssertTrue(button.waitForExistence(timeout: 3))
    }
    func testPrefabRuntimeKeepsLocalStoryDistinctFromSync() {
        let app = launch("playPrefab")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "playx.prefab.runtime").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(revealFixtureElement(app.buttons["Continue story"], in: app), app.debugDescription)
        XCTAssertFalse(app.staticTexts["On-site record confirmed by readback"].exists)
    }
    func testPrefabBootAcceptsExactSourcePhrase() {
        let app = launch("playPrefabBoot")
        let field = app.textFields["playx.prefab.boot.input"]
        XCTAssertTrue(revealFixtureElement(field, in: app), app.debugDescription)
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: field); waitForExpectations(timeout: 5)
        field.tap(); field.typeText("hello world")
        XCTAssertTrue(app.buttons["Continue walking animation"].waitForExistence(timeout: 3))
    }
    func testDirectorChineseLabels() {
        let app = launch("playDirector", language: "zh-Hans")
        XCTAssertTrue(app.navigationBars["活动导演台"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["playx.director.action.FINISH"].exists)
    }
}
