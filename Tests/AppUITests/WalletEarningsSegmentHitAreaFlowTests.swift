import XCTest

final class WalletEarningsSegmentHitAreaFlowTests: XCTestCase {
    func testLargeTextSegmentEdgesSelectNativeTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--wallet-commerce-fixture", "--wallet-earnings-overview-fixture",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_Hans_CN",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        app.launch()
        defer { app.terminate() }
        app.buttons["wallet.fixture.income"].tap()
        let income = app.buttons["wallet.earnings.tab.income"]
        let organizer = app.buttons["wallet.earnings.tab.organizer"]
        XCTAssertTrue(organizer.waitForExistence(timeout: 5))
        XCTAssertEqual(organizer.label, "主办分润")
        for button in [income, organizer] {
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertTrue(button.isHittable)
        }
        organizer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        XCTAssertTrue(organizer.isSelected)
        income.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        XCTAssertTrue(income.isSelected)
        XCTAssertFalse(organizer.isSelected)
    }
}
