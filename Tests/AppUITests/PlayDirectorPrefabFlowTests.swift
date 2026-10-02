import XCTest

final class PlayDirectorPrefabFlowTests: XCTestCase {
    private func launch(_ module: String, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-module", module, "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch(); return app
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
        for _ in 0..<5 { if button.exists && button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        XCTAssertTrue(app.navigationBars["Activity director"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap(); XCTAssertTrue(button.waitForExistence(timeout: 3))
    }
    func testPrefabRuntimeKeepsLocalStoryDistinctFromSync() {
        let app = launch("playPrefab")
        XCTAssertTrue(app.otherElements["playx.prefab.runtime"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue story"].exists)
        XCTAssertFalse(app.staticTexts["On-site record confirmed by readback"].exists)
    }
    func testPrefabBootAcceptsExactSourcePhrase() {
        let app = launch("playPrefabBoot")
        let field = app.textFields["playx.prefab.boot.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("hello world")
        XCTAssertTrue(app.buttons["Continue walking animation"].waitForExistence(timeout: 3))
    }
    func testDirectorChineseLabels() {
        let app = launch("playDirector", language: "zh-Hans")
        XCTAssertTrue(app.navigationBars["活动导演台"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["playx.director.action.FINISH"].exists)
    }
}
