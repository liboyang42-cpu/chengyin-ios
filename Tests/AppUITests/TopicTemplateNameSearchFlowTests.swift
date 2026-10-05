import XCTest

/// Authored synthetic UI coverage. Runtime and accessibility validation require Apple execution.
final class TopicTemplateNameSearchFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "publicPlayTemplate",
                               "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        if chinese { app.launchArguments += ["--uitesting-max-text", "--uitesting-dark", "--uitesting-reduce-motion"] }
        app.launch()
        if chinese { assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility5") }
        XCTAssertTrue(app.textFields["discovery.topicNameSearch"].waitForExistence(timeout: 10), app.debugDescription)
    }
    private func tap(_ id: String) {
        let element = app.buttons.matching(identifier: id).firstMatch
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription); element.tap()
    }
    private func search(_ text: String) {
        let field = app.textFields["discovery.topicNameSearch"]
        XCTAssertTrue(revealFixtureElement(field, in: app), app.debugDescription)
        field.tap(); field.typeText(text)
        tap("discovery.topicNameSearch.submit")
    }
    private func expect(_ element: XCUIElement, _ predicate: String) {
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 10), .completed, app.debugDescription)
    }
    func testTopicNameSearchAppliesCaseAndWhitespaceThenClearsNoMatches() {
        launch()
        search("  NeIgHbOrHoOd  ")
        expect(app.staticTexts["discovery.topicNameSearch.applied"], "label == 'NeIgHbOrHoOd'")
        XCTAssertTrue(app.buttons["discovery.topic.801"].exists)
        XCTAssertFalse(app.buttons["discovery.topic.802"].exists)
        tap("discovery.topicNameSearch.clear")
        search("not a loaded template")
        XCTAssertTrue(app.descendants(matching: .any)["discovery.topicNameSearch.noResults"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["discovery.topic.801"].exists)
        XCTAssertFalse(app.buttons["discovery.topic.802"].exists)
        tap("discovery.topicNameSearch.clear")
        XCTAssertTrue(app.buttons["discovery.topic.801"].exists)
        XCTAssertTrue(app.buttons["discovery.topic.802"].exists)
    }
    func testTopicNameSearchRemainsIndependentFromGameKeywordAcrossTabs() {
        launch(); search("progress")
        XCTAssertTrue(app.buttons["discovery.topic.802"].exists)
        let picker = app.segmentedControls["discovery.shelf"]
        picker.buttons.element(boundBy: 1).tap()
        let game = app.textFields["discovery.search"]
        XCTAssertTrue(game.waitForExistence(timeout: 10)); game.tap(); game.typeText("Notice\n")
        XCTAssertTrue(app.buttons["discovery.play.701"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["discovery.play.702"].exists)
        picker.buttons.element(boundBy: 0).tap()
        expect(app.staticTexts["discovery.topicNameSearch.applied"], "label == 'progress'")
        XCTAssertTrue(app.buttons["discovery.topic.802"].exists)
        XCTAssertFalse(app.buttons["discovery.topic.801"].exists)
        tap("discovery.topicNameSearch.clear")
        picker.buttons.element(boundBy: 1).tap()
        expect(app.textFields["discovery.search"], "value == 'Notice'")
        XCTAssertTrue(app.buttons["discovery.play.701"].exists)
        XCTAssertFalse(app.buttons["discovery.play.702"].exists)
    }
    func testChineseMaximumTextSearchDetailBackAndReloadKeepLocalScope() {
        launch(chinese: true); search("neighborhood")
        XCTAssertTrue(revealFixtureElement(app.staticTexts["仅搜索此处已加载的主题模板。"].firstMatch, in: app))
        tap("discovery.topic.801")
        XCTAssertTrue(app.staticTexts["A neighborhood in three chapters"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["templateAuthor.adopt"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(revealFixtureElement(app.textFields["discovery.topicNameSearch"], in: app))
        app.swipeDown()
        expect(app.staticTexts["discovery.topicNameSearch.applied"], "label == 'neighborhood'")
        XCTAssertTrue(revealFixtureElement(app.buttons["discovery.topic.801"], in: app))
        XCTAssertFalse(app.buttons["discovery.topic.802"].exists)
        tap("discovery.topicNameSearch.clear")
        tap("discovery.topic.802")
        XCTAssertTrue(app.staticTexts["discovery.publicTotalStops"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["templateAuthor.adopt"].exists)
    }
}
