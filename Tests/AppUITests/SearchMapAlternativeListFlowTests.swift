import XCTest

/// Offline authored UI tests. Requires ModuleFixture.searchMap. No provider/location runtime.
final class SearchMapAlternativeListFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func launch(_ scenario: String = "content", entry: String = "global", chinese: Bool = false, accessible: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "searchMap", "--uitesting-search-map-scenario", scenario, "--uitesting-search-map-entry", entry]
        if accessible { app.launchArguments += ["--uitesting-large-text","--uitesting-dark","--uitesting-reduce-motion"] }
        app.launch()
        if accessible { assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility3") }
    }
    private func reveal(_ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<12 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.exists, app.debugDescription); XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func search(_ text: String = "sample") {
        let field = app.textFields["searchMap.keyword"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(text + "\n")
    }

    private func openGlobalFilters() {
        XCTAssertTrue(revealFixtureElement(app.buttons["searchMap.filters"], in: app, towardTop: true))
        app.buttons["searchMap.filters"].tap()
    }
    private func chooseCategory(_ title: String) {
        let picker = app.buttons["searchMap.filter.category"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        let category = app.buttons[title]
        XCTAssertTrue(category.waitForExistence(timeout: 5)); category.tap()
    }
    private func releaseGlobalSearch(latest: Bool = true) {
        let button = app.buttons[latest ? "searchMap.fixture.releaseLastSearch" : "searchMap.fixture.releaseFirstSearch"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    private func assertCategoryRows(_ id: Int) {
        for kind in ["topic", "activity", "club", "merchant"] {
            XCTAssertTrue(app.buttons["searchMap.result.\(kind)-\(id)"].waitForExistence(timeout: 5), app.debugDescription)
        }
    }

    private func verifyMapMarkerSelection(accessible: Bool) {
        launch(entry: "markerStyle", accessible: accessible)
        let merchant = app.buttons["searchMap.pin.style-merchant"]
        let activity = app.buttons["searchMap.pin.style-activity"]
        reveal(merchant); XCTAssertFalse(merchant.isSelected); merchant.tap()
        XCTAssertTrue(merchant.isSelected)
        reveal(activity); XCTAssertFalse(activity.isSelected); activity.tap()
        XCTAssertTrue(activity.isSelected); XCTAssertFalse(merchant.isSelected)
        XCTAssertEqual(activity.label, "A very long neighborhood discovery walk with the complete destination name · 城市街区探索漫步与完整目的地名称，重要信息保留到最后")
        let clear = app.buttons["mapStyle.fixture.clear"]; reveal(clear); clear.tap()
        XCTAssertFalse(activity.isSelected); XCTAssertFalse(merchant.isSelected)
    }

    private func launchAlternativeList(chinese: Bool = false, maximumType: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
            "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "searchMap",
            "--uitesting-search-map-entry", "alternativeList"]
        if maximumType { app.launchArguments += ["--uitesting-max-text", "--uitesting-dark", "--uitesting-reduce-motion"] }
        app.launch()
        if maximumType { assertFixtureEnvironment(in: app, colorScheme: "dark", dynamicTypeSize: "accessibility5") }
    }
    private func alternativeListButton(_ id: String, towardTop: Bool = false) -> XCUIElement {
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        // A complete, untruncated accessibility-size title can be taller than the
        // viewport. Requiring its entire button frame to fit would be impossible.
        if id.hasPrefix("mapList.pin."), button.frame.height > app.frame.height - 220 {
            for _ in 0..<20 {
                if button.isHittable { return button }
                if towardTop { app.swipeDown() } else { app.swipeUp() }
            }
            XCTFail("Long list row is not reachable: " + app.debugDescription)
            return button
        }
        XCTAssertTrue(revealFixtureElement(button, in: app, towardTop: towardTop, maximumSwipes: 20), app.debugDescription)
        return button
    }
    private func tapAlternativeListRow(_ id: String, towardTop: Bool = false) {
        let button = alternativeListButton(id, towardTop: towardTop)
        let visible = button.frame.intersection(app.scrollViews.firstMatch.frame)
            .intersection(app.frame.insetBy(dx: 12, dy: 100))
        XCTAssertFalse(visible.isEmpty, app.debugDescription)
        guard !visible.isEmpty, button.frame.width > 0, button.frame.height > 0 else { return }
        button.coordinate(withNormalizedOffset: CGVector(dx: (visible.midX - button.frame.minX) / button.frame.width,
            dy: (visible.midY - button.frame.minY) / button.frame.height)).tap()
    }
    func testAlternativeListBilingualMaximumTypeKeepsFullTitlesAndParentSelectionInSync() {
        for chinese in [false, true] {
            launchAlternativeList(chinese: chinese, maximumType: true)
            alternativeListButton("mapList.fixture.pointSecond").tap()
            let toggle = alternativeListButton("mapList.toggle")
            XCTAssertEqual(toggle.label, chinese ? "以列表查看地点" : "Show places as a list")
            toggle.tap()
            let first = alternativeListButton("mapList.pin.list-first")
            XCTAssertEqual(first.label, "A very long neighborhood discovery walk with the complete destination name · 城市街区探索漫步与完整目的地名称，重要信息保留到最后")
            XCTAssertFalse(first.isSelected)
            let second = alternativeListButton("mapList.pin.list-second")
            XCTAssertTrue(second.isSelected)
            XCTAssertEqual(second.value as? String, chinese ? "已选中" : "Selected")
            tapAlternativeListRow("mapList.pin.list-first", towardTop: true)
            XCTAssertTrue(app.buttons["mapList.pin.list-first"].isSelected)
            XCTAssertFalse(app.buttons["mapList.pin.list-second"].isSelected)
            alternativeListButton("mapList.fixture.clear", towardTop: true).tap()
            XCTAssertEqual(app.staticTexts["mapList.fixture.selection"].label, "none")
            XCTAssertFalse(app.buttons["mapList.pin.list-first"].isSelected)
            XCTAssertFalse(app.buttons["mapList.pin.list-second"].isSelected)
            app.terminate()
        }
    }
    func testAlternativeListRefreshRemovalAndDuplicateIDsCannotSelectAnotherPlace() {
        launchAlternativeList()
        alternativeListButton("mapList.toggle").tap()
        alternativeListButton("mapList.pin.list-first").tap()
        alternativeListButton("mapList.fixture.duplicates", towardTop: true).tap()
        XCTAssertFalse(app.buttons["mapList.pin.list-first"].exists)
        alternativeListButton("mapList.pin.list-second").tap()
        XCTAssertTrue(app.buttons["mapList.pin.list-second"].isSelected)
        alternativeListButton("mapList.fixture.refreshed", towardTop: true).tap()
        let refreshed = alternativeListButton("mapList.pin.list-first")
        XCTAssertEqual(refreshed.label, "Refreshed public entrance · 更新后的公开入口")
        refreshed.tap()
        XCTAssertTrue(refreshed.isSelected)
        alternativeListButton("mapList.fixture.removed", towardTop: true).tap()
        XCTAssertFalse(app.buttons["mapList.pin.list-first"].exists)
        let remaining = alternativeListButton("mapList.pin.list-second")
        XCTAssertFalse(remaining.isSelected); remaining.tap()
        XCTAssertTrue(remaining.isSelected)
    }
    func testAlternativeListCloseReopenAndEmptySnapshotNeverRetainOldRows() {
        launchAlternativeList()
        alternativeListButton("mapList.toggle").tap()
        alternativeListButton("mapList.pin.list-first").tap()
        alternativeListButton("mapList.toggle", towardTop: true).tap()
        XCTAssertFalse(app.buttons["mapList.pin.list-first"].exists)
        alternativeListButton("mapList.toggle").tap()
        XCTAssertTrue(alternativeListButton("mapList.pin.list-first").isSelected)
        alternativeListButton("mapList.fixture.empty", towardTop: true).tap()
        XCTAssertFalse(app.buttons["mapList.pin.list-first"].exists)
        XCTAssertFalse(app.buttons["mapList.pin.list-second"].exists)
        XCTAssertTrue(app.staticTexts["mapList.empty"].exists)
        alternativeListButton("mapList.fixture.normal", towardTop: true).tap()
        alternativeListButton("mapList.pin.list-second").tap()
        XCTAssertTrue(app.buttons["mapList.pin.list-second"].isSelected)
        alternativeListButton("mapList.fixture.readOnly", towardTop: true).tap()
        XCTAssertFalse(app.buttons["mapList.pin.list-first"].isEnabled)
        XCTAssertFalse(app.buttons["mapList.pin.list-second"].isEnabled)
        alternativeListButton("mapList.fixture.normal", towardTop: true).tap()
        alternativeListButton("mapList.fixture.depart", towardTop: true).tap()
        XCTAssertTrue(app.staticTexts["mapList.fixture.away"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let returnedToggle = alternativeListButton("mapList.toggle")
        XCTAssertTrue(returnedToggle.isEnabled)
        XCTAssertFalse(app.buttons["mapList.pin.list-first"].exists)
        returnedToggle.tap()
        alternativeListButton("mapList.pin.list-first").tap()
        XCTAssertTrue(app.buttons["mapList.pin.list-first"].isSelected)
    }
}
