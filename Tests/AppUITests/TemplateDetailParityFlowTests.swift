import XCTest

/// Offline mini-program templatedetail parity (评价, 怎么验证, 节点交互预览, 官方 badge).
/// Synthetic rows only; no account or network. Apple execution is unrun in the Linux sandbox.
final class TemplateDetailParityFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func app(_ scenario: String, chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "templateDetailParity", "--template-parity-scenario", scenario,
                               "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US"]
        runningApp = app; app.launch()
        XCTAssertTrue(element("discovery.detail.content", app).waitForExistence(timeout: 10), app.debugDescription)
        return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func gone(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }
    private func reveal(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        let target = element(id, app)
        XCTAssertTrue(revealFixtureElement(target, in: app), app.debugDescription)
        return target
    }

    func testChoicePreviewNeedsAnAnswerAndReviewsShowCount() {
        let app = app("choice")
        XCTAssertTrue(reveal("discovery.templateDetail.reviews", app).label.contains("3 from real players"))
        XCTAssertTrue(reveal("discovery.templateDetail.publisher", app).label.contains("Creator"))
        reveal("discovery.templateDetail.previewNode", app).tap()
        XCTAssertTrue(element("discovery.templateDetail.preview", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("discovery.templateDetail.preview.option.C", app).exists)
        app.buttons["discovery.templateDetail.preview.complete"].tap()
        XCTAssertTrue(element("discovery.templateDetail.preview.answerFirst", app).waitForExistence(timeout: 3))
        app.buttons["discovery.templateDetail.preview.option.B"].tap()
        app.buttons["discovery.templateDetail.preview.complete"].tap()
        XCTAssertTrue(gone(element("discovery.templateDetail.preview", app)))
    }

    func testOfficialPlatformContentAndUnsupportedPreviewInChinese() {
        let app = app("official", chinese: true)
        XCTAssertTrue(reveal("discovery.templateDetail.publisher", app).label.contains("官方"))
        XCTAssertTrue(reveal("discovery.templateDetail.notice", app).label.contains("不能直接开团"))
        XCTAssertFalse(element("discovery.templateDetail.reviews", app).exists, "no rating, no 评价 section")
        reveal("discovery.templateDetail.previewNode", app).tap()
        XCTAssertTrue(app.staticTexts["该玩法验证方式为「Photo」，请报名参与活动后体验。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["discovery.templateDetail.preview.complete"].exists)
        app.buttons["discovery.templateDetail.preview.close"].tap()
        XCTAssertTrue(gone(element("discovery.templateDetail.preview", app)))
    }

    func testTopicTemplateShowsChapterStatsWithoutPreview() {
        let app = app("topic")
        XCTAssertTrue(reveal("discovery.templateDetail.stat.chapters", app).label.contains("3"))
        XCTAssertTrue(element("discovery.templateDetail.stat.nodes", app).label.contains("6"))
        XCTAssertFalse(element("discovery.templateDetail.previewNode", app).exists)
    }
}
