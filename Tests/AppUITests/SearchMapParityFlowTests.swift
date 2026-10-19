import XCTest

/// Mini-program pages/searchmap parity over the offline `searchMap` fixture module.
/// Synthetic rows and synthetic connectivity only; no location, provider or live network.
final class SearchMapParityFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(offline: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                               "--uitesting-module", "searchMap", "--uitesting-search-map-scenario", "content",
                               "--uitesting-search-map-entry", "city"]
        if offline { app.launchArguments.append("--uitesting-search-map-offline") }
        app.launch()
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testOfflineBannerShowsCacheStateAndClearsOnReconnect() {
        launch(offline: true)
        let message = element("searchMap.w208.offline.message")
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.contains("尚无可用的活动缓存"), message.label)
        app.buttons["searchMap.searchArea"].tap()
        XCTAssertTrue(element("searchMap.w208.offline.cachedAt").waitForExistence(timeout: 5))
        XCTAssertTrue(element("searchMap.w208.offline.message").label.contains("来自上次加载"))
        app.buttons["searchMap.w208.offline.retry"].tap()
        XCTAssertTrue(element("searchMap.w208.offline.stillOffline").waitForExistence(timeout: 5))
        app.buttons["searchMap.fixture.network"].tap()
        XCTAssertTrue(element("searchMap.w208.offline").waitForNonExistence(timeout: 5))
    }

    func testCapsuleOpensAllResultsSheetWithListOnlyTipAndOpensActivity() {
        launch()
        app.buttons["searchMap.searchArea"].tap()
        let capsule = app.buttons["searchMap.w208.capsule"]
        XCTAssertTrue(revealFixtureElement(capsule, in: app))
        XCTAssertTrue(capsule.label.contains("查看全部 2 个结果"), capsule.label)
        XCTAssertTrue(capsule.label.contains("1 个活动只在列表显示"), capsule.label)
        capsule.tap()
        XCTAssertTrue(app.navigationBars["全部 2 个结果"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("searchMap.w208.sheet.listOnlyTip").exists)
        app.buttons["searchMap.w208.sheet.activity.71"].tap()
        XCTAssertTrue(element("searchMap.destination.activity.71").waitForExistence(timeout: 5))
    }

    func testSelectedActivityHasExplicitDetailButtonAndNodeShowsLevel() {
        launch()
        app.buttons["searchMap.searchArea"].tap()
        let node = app.buttons["searchMap.select.city-71"]
        XCTAssertTrue(revealFixtureElement(node, in: app)); node.tap()
        let level = element("searchMap.w208.selected.level")
        XCTAssertTrue(level.waitForExistence(timeout: 5))
        XCTAssertTrue(level.label.contains("官方合作"), level.label)
        let activity = app.buttons["searchMap.select.activity-71"]
        XCTAssertTrue(revealFixtureElement(activity, in: app)); activity.tap()
        let open = app.buttons["searchMap.w208.selected.viewActivity.71"]
        XCTAssertTrue(revealFixtureElement(open, in: app))
        XCTAssertEqual(open.label, "查看活动详情")
        open.tap()
        XCTAssertTrue(element("searchMap.destination.activity.71").waitForExistence(timeout: 5))
    }

}
