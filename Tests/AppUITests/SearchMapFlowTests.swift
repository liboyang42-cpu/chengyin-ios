import XCTest

/// Offline authored UI tests. Requires ModuleFixture.searchMap. No provider/location runtime.
final class SearchMapFlowTests: XCTestCase {
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
    func testGlobalDomainsAreSeparateAndMerchantDetailUsesMerchantID() {
        launch(); search()
        let merchantFilter = app.buttons["searchMap.kind.merchant"]; reveal(merchantFilter); merchantFilter.tap()
        let row = app.buttons["searchMap.result.merchant-71"]; reveal(row); row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["searchMap.merchant.detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic shop"].exists)
        XCTAssertFalse(app.staticTexts["999"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["searchMap.result.merchant-71"].waitForExistence(timeout: 5))
    }
    func testGuestKeepsPublicResultsAndShowsExplicitGate() {
        launch("guest"); search()
        XCTAssertTrue(app.descendants(matching: .any)["searchMap.guestGate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["searchMap.result.topic-71"].exists)
        XCTAssertFalse(app.buttons["searchMap.result.club-71"].exists)
    }
    func testPartialFailureDoesNotBecomeEmptyWholePage() {
        launch("partial"); search()
        XCTAssertTrue(app.descendants(matching: .any)["searchMap.partialFailure"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["searchMap.result.topic-71"].exists)
        XCTAssertFalse(app.buttons["searchMap.result.merchant-71"].exists)
    }
    func testFilterValidationCancelAndReopen() {
        launch(); app.buttons["searchMap.filters"].tap()
        let minimum = app.textFields["searchMap.filter.min"]; minimum.tap(); minimum.typeText("70")
        let maximum = app.textFields["searchMap.filter.max"]; maximum.tap(); maximum.typeText("20")
        app.buttons["searchMap.filter.apply"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["searchMap.filter.invalid"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap(); app.buttons["searchMap.filters"].tap()
        XCTAssertEqual(app.textFields["searchMap.filter.min"].value as? String, "Minimum (0–1000)")
    }
    func testCityMissingCoordinatesStayInListAndNodeOpensCorrectDomain() {
        launch(entry: "city"); app.buttons["searchMap.searchArea"].tap()
        let missing = app.buttons["searchMap.city.activity.73"]; reveal(missing)
        let node = app.buttons["searchMap.city.node.71"]; reveal(node); node.tap()
        XCTAssertTrue(app.descendants(matching: .any)["searchMap.city.detail"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic city node"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic route stop"].exists)
    }
    func testNearbyRouteNodeUsesTopicReferenceAndHonestRoutePreview() {
        launch("cityFallback", entry: "nearby"); app.buttons["searchMap.searchArea"].tap()
        let node = app.buttons["searchMap.nearby.node.71"]; reveal(node); node.tap()
        app.buttons["searchMap.openRoute"].tap()
        XCTAssertTrue(app.staticTexts["Walking route unavailable. No walkable path has been verified."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start navigation"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["Driving"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.route.fallback"].exists)
    }
    func testSessionSwitchClearsResultsAndCityData() {
        launch(); search(); XCTAssertTrue(app.buttons["searchMap.result.topic-71"].waitForExistence(timeout: 5))
        app.buttons["searchMap.fixture.guest"].tap()
        XCTAssertFalse(app.buttons["searchMap.result.topic-71"].exists)
        search(); XCTAssertTrue(app.descendants(matching: .any)["searchMap.guestGate"].waitForExistence(timeout: 5))
    }
    func testRetryRecovers() {
        launch("retry"); search()
        let retry = app.buttons["Retry"].firstMatch; XCTAssertTrue(retry.waitForExistence(timeout: 5)); retry.tap()
        XCTAssertTrue(app.buttons["searchMap.result.topic-71"].waitForExistence(timeout: 5))
    }
    func testEnglishAndChineseRoutePreviewLargeTypeDarkReduceMotion() {
        for chinese in [false,true] {
            launch(entry: "route", chinese: chinese, accessible: true)
            XCTAssertTrue(app.navigationBars[chinese ? "路线预览" : "Route preview"].waitForExistence(timeout: 5))
            reveal(app.staticTexts[chinese ? "步行路线不可用，尚未确认可通行道路" : "Walking route unavailable. No walkable path has been verified."])
            app.terminate()
        }
    }
    func testCityListSelectionUsesSamePinAndPreservesExplicitMapGate() {
        launch(entry: "city"); app.buttons["searchMap.searchArea"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.map"].exists)
        let select = app.buttons["searchMap.select.city-71"]; reveal(select); select.tap()
        XCTAssertTrue(app.descendants(matching: .any)["searchMap.selectedSummary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.map"].exists)
        XCTAssertTrue(revealFixtureElement(app.buttons["searchMap.showMap"], in: app, towardTop: true))
        app.buttons["searchMap.showMap"].tap()
        XCTAssertTrue(app.buttons["searchMap.pin.city-71"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["searchMap.pin.city-71"].isSelected)
        app.buttons["searchMap.pin.activity-71"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["searchMap.selectedSummary"].exists)
        let clear = app.buttons["searchMap.selection.clear"]; reveal(clear); clear.tap()
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.selectedSummary"].exists)
    }
    func testCityFilterCancelPreservesSelectionButApplyClearsIt() {
        launch(entry: "city"); app.buttons["searchMap.searchArea"].tap()
        let select = app.buttons["searchMap.select.city-71"]; reveal(select); select.tap()
        XCTAssertTrue(revealFixtureElement(app.buttons["searchMap.filters"], in: app, towardTop: true))
        app.buttons["searchMap.filters"].tap()
        let tag = app.textFields["searchMap.tag"]; XCTAssertTrue(tag.waitForExistence(timeout: 5)); tag.tap(); tag.typeText("unsaved")
        app.buttons["searchMap.filter.cancel"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["searchMap.selectedSummary"].exists)
        app.buttons["searchMap.filters"].tap()
        XCTAssertNotEqual(app.textFields["searchMap.tag"].value as? String, "unsaved")
        app.buttons["searchMap.filter.apply"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.selectedSummary"].exists)
        XCTAssertFalse(app.buttons["searchMap.city.node.71"].exists)
    }
    func testCityLoadingRetryAndScopeChangeNeverKeepSelectedPlace() {
        launch("delayed", entry: "city"); app.buttons["searchMap.searchArea"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["searchMap.loading"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["searchMap.city.node.71"].exists)
        app.buttons["searchMap.fixture.releaseCitySearch"].tap()
        XCTAssertTrue(app.buttons["searchMap.city.node.71"].waitForExistence(timeout: 5))
        app.terminate()
        launch("retry", entry: "city"); app.buttons["searchMap.searchArea"].tap()
        let retry = app.buttons["Retry"].firstMatch; reveal(retry); retry.tap()
        let select = app.buttons["searchMap.select.city-71"]; reveal(select); select.tap()
        app.buttons["searchMap.fixture.account"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.selectedSummary"].exists)
        XCTAssertFalse(app.buttons["searchMap.city.node.71"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.map"].exists)
    }
    func testCityEmptyStateRemainsExplicit() {
        launch("empty", entry: "city"); app.buttons["searchMap.searchArea"].tap()
        XCTAssertTrue(app.staticTexts["No matching results"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.selectedSummary"].exists)
    }

    func testManualAreaChangeClearsSelectionAndRequiresMapOptInAgain() {
        launch(entry: "city"); app.buttons["searchMap.searchArea"].tap()
        app.buttons["searchMap.showMap"].tap()
        let pin = app.buttons["searchMap.pin.city-71"]; reveal(pin); pin.tap()
        XCTAssertTrue(revealFixtureElement(app.buttons["searchMap.chooseArea"], in: app, towardTop: true))
        app.buttons["searchMap.chooseArea"].tap()
        let latitude = app.textFields["roam.area.latitude.input"]
        XCTAssertTrue(latitude.waitForExistence(timeout: 5)); latitude.tap(); latitude.typeText("2")
        let longitude = app.textFields["roam.area.longitude.input"]; longitude.tap(); longitude.typeText("3")
        app.buttons["roam.area.select"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.selectedSummary"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["searchMap.map"].exists)
        XCTAssertFalse(app.buttons["searchMap.city.node.71"].exists)
        XCTAssertTrue(app.buttons["searchMap.showMap"].exists)
    }

}
