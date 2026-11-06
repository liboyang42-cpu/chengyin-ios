import XCTest

/// Uses the existing manual-point offline host; never requests device location.
final class NearbyTeamCountAccessibilityFlowTests: XCTestCase {
    func testChineseCountIsTextNotDecorativeCircle() {
        verify(language: "zh-Hans", expected: "附近的队伍 · 6 支在招募")
    }

    func testEnglishCountIsTextNotDecorativeCircle() {
        verify(language: "en", expected: "Nearby teams · 6 recruiting")
    }

    private func verify(language: String, expected: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--nearby-team-fixture",
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        app.launch()
        defer { app.terminate() }
        let titles = app.staticTexts.matching(identifier: "nearby.w208.header")
        let loaded = NSPredicate(format: "label == %@", expected)
        expectation(for: loaded, evaluatedWith: titles.firstMatch)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(titles.count, 1)
        XCTAssertFalse(app.images["nearby.w208.header"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "nearby.w208.header").firstMatch.label, expected)
        XCTAssertFalse(app.textFields["nearby.latitude"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
}
