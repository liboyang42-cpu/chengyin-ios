import XCTest

final class ActivityDetailTitleAccessibilityFlowTests: XCTestCase {
    func testTitleFocusExcludesDecorativeCoverAndSurvivesReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-activity-fixture", "tickets",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        defer { app.terminate() }
        for _ in 0..<2 {
            let row = app.buttons["activity.row.101"]
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            row.tap()
            let titles = app.staticTexts.matching(identifier: "activity.detail.name")
            let title = titles.firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 8))
            XCTAssertEqual(titles.count, 1)
            XCTAssertEqual(title.label, "Fixture ticket activity")
            // The unchanged fixture uses ordinary text size. Its title must not inherit
            // the 160pt decorative cover, let alone the original 269.7pt list-cell frame.
            XCTAssertLessThan(title.frame.height, 160)
            XCTAssertTrue(title.isHittable)
            XCTAssertFalse(app.buttons["activity.openRegistration"].exists)
            XCTAssertFalse(app.buttons["payment.pay"].exists)
            app.navigationBars["Activity details"].buttons.firstMatch.tap()
        }
    }
}
