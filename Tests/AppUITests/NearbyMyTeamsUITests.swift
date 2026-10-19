import XCTest

/// 我的队伍 grouping in the DEBUG-only `--nearby-team-fixture` host. Synthetic rows; no location or live session.
final class NearbyMyTeamsUITests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() { attachFailureScreenshot(self, app: runningApp); runningApp?.terminate(); runningApp = nil; super.tearDown() }
    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-reset-language", "--nearby-team-fixture", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
        runningApp = app; app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testMineTabGroupsLeadApprovedPendingRejectedWithCounts() {
        let app = launch(language: "zh-Hans")
        XCTAssertTrue(app.segmentedControls["nearby.section"].waitForExistence(timeout: 5))
        app.segmentedControls["nearby.section"].buttons.element(boundBy: 1).tap()
        let leading = element("nearby.mine.group.leading", app)
        XCTAssertTrue(revealFixtureElement(leading, in: app, requiresHittable: false))
        XCTAssertEqual(leading.label, "我带的队")
        XCTAssertTrue(element("nearby.joined.503", app).exists)
        XCTAssertTrue(element("nearby.mine.stat.leading", app).label.contains("带队"))
        XCTAssertTrue(element("nearby.mine.stat.approved", app).label.contains("1"))
        XCTAssertTrue(revealFixtureElement(element("nearby.mine.group.approved", app), in: app, requiresHittable: false))
        XCTAssertTrue(revealFixtureElement(element("nearby.joined.505", app), in: app, requiresHittable: false))
        XCTAssertTrue(revealFixtureElement(element("nearby.mine.group.pending", app), in: app, requiresHittable: false))
        XCTAssertTrue(revealFixtureElement(app.buttons["nearby.withdraw.502"], in: app))
        XCTAssertTrue(revealFixtureElement(element("nearby.mine.group.rejected", app), in: app, requiresHittable: false))
        XCTAssertFalse(element("nearby.joined.507", app).exists, "Ended teams are omitted like the mini-program")
        XCTAssertFalse(element("nearby.mine.findOnMap", app).exists)
    }
}
