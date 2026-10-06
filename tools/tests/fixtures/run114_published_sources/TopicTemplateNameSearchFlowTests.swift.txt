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
        if ["discovery.topic.801", "discovery.topic.802"].contains(id) {
            guard let (button, visible) = revealedTopicCard(id) else { return }
            let frame = button.frame
            // Exact card, visible content region, never an arbitrary screen coordinate.
            button.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: visible.midX - frame.minX, dy: visible.midY - frame.minY)).tap()
            return
        }
        let element = app.buttons.matching(identifier: id).firstMatch
        XCTAssertTrue(revealFixtureElement(element, in: app), app.debugDescription)
        XCTAssertTrue(element.isHittable, app.debugDescription); element.tap()
    }
    /// Accessibility5 can make this exact card taller than the entire viewport.
    /// Such a real button is still tappable through its visible region; demanding
    /// its complete 845pt frame makes a bounded scroll helper loop forever.
    private func revealedTopicCard(_ id: String) -> (XCUIElement, CGRect)? {
        guard ["discovery.topic.801", "discovery.topic.802"].contains(id) else { XCTFail("Unknown topic fixture card"); return nil }
        let query = app.buttons.matching(identifier: id)
        let title = app.launchArguments.contains("(zh-Hans)") ? "浏览模板" : "Browse templates"
        let bar = app.navigationBars[title]
        for attempt in 0...12 {
            guard bar.exists, !bar.frame.isEmpty else { XCTFail("Expected topic browser navigation bar: " + app.debugDescription); return nil }
            var bounds = app.frame.insetBy(dx: 4, dy: 4)
            bounds.origin.y = max(bounds.minY, bar.frame.maxY + 4)
            var bottom = app.frame.maxY - 40
            for keyboard in app.keyboards.allElementsBoundByIndex where keyboard.exists { bottom = min(bottom, keyboard.frame.minY - 4) }
            bounds.size.height = max(0, bottom - bounds.minY)
            var towardTop = false
            if query.count == 1 {
                let button = query.element(boundBy: 0), frame = button.frame
                let visible = frame.intersection(bounds)
                let oversized = frame.height > bounds.height
                if button.exists && button.isEnabled && button.isHittable && !frame.isEmpty &&
                    !visible.isNull && visible.width >= 44 && visible.height >= 44 &&
                    frame.minX >= bounds.minX && frame.maxX <= bounds.maxX &&
                    (oversized || bounds.contains(frame)) {
                    return (button, visible)
                }
                towardTop = !frame.isEmpty && frame.midY < bounds.midY
            } else if query.count > 1 { XCTFail("Ambiguous topic card identifier: " + app.debugDescription); return nil }
            guard attempt < 12, bounds.height > 80 else { break }
            let x = (bounds.midX - app.frame.minX) / app.frame.width
            let start = (bounds.minY - app.frame.minY + bounds.height * (towardTop ? 0.3 : 0.75)) / app.frame.height
            let end = (bounds.minY - app.frame.minY + bounds.height * (towardTop ? 0.75 : 0.3)) / app.frame.height
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: start)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: end)))
        }
        XCTFail("Exact topic card has no safe enabled visible region: " + app.debugDescription); return nil
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
        XCTAssertNotNil(revealedTopicCard("discovery.topic.801"))
        XCTAssertFalse(app.buttons["discovery.topic.802"].exists)
        tap("discovery.topicNameSearch.clear")
        tap("discovery.topic.802")
        XCTAssertTrue(app.staticTexts["discovery.publicTotalStops"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["templateAuthor.adopt"].exists)
    }
}
