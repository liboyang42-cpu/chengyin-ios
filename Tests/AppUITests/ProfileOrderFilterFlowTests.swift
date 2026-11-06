import XCTest

@MainActor final class ProfileOrderFilterFlowTests: XCTestCase {
    private var app:XCUIApplication!
    private var capturedFirstFailure = false
    override func setUp() { continueAfterFailure=false; app=XCUIApplication(); capturedFirstFailure=false }
    private func captureFirstFailure(expected: String) {
        guard !capturedFirstFailure else { return }
        capturedFirstFailure = true
        // This suite launches only the sealed in-memory fixture. Never dump production session data.
        let revoke = app.buttons["profile.orderFilter.fixture.revoke"]
        let configured = revoke.exists ? String(describing: revoke.value ?? "missing") : "control absent"
        let list = app.staticTexts["profile.orderFilter.fixture.listReads"]
        let detail = app.staticTexts["profile.orderFilter.fixture.detailReads"]
        let state = "configured=\(configured),listReads=\(list.exists ? list.label : "absent"),detailReads=\(detail.exists ? detail.label : "absent")"
        let hierarchy = app.debugDescription
        print("PROFILE_ORDER_FILTER_FIRST_FAILURE expected=\(expected)\nSTATE:\n\(state)\nAX:\n\(hierarchy)")
        XCTContext.runActivity(named: "First order-filter failure: \(expected)") { activity in
            let evidence = XCTAttachment(string: "Expected: \(expected)\n\(state)\n\(hierarchy)")
            evidence.name = "Synthetic order filter state and AX"; evidence.lifetime = .keepAlways; activity.add(evidence)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Order filter first failure"; screenshot.lifetime = .keepAlways; activity.add(screenshot)
        }
    }
    private func launch(empty:Bool=false) {
        app.launchArguments=["--uitesting-reset-language","--uitesting-profile-order-filters","-AppleLanguages","(en)","-AppleLocale","en_US"] + (empty ? ["--profile-order-filters-empty"] : [])
        app.launch()
    }
    /// Source chip row: every filter is a visible chip; scroll the row until the chip is hittable.
    private func choose(_ filter:String, label:String) {
        let row=app.descendants(matching: .any).matching(identifier: "profile.orderFilter.picker").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:5))
        let option=app.buttons["profile.orderFilter.chip.\(filter)"];XCTAssertTrue(option.waitForExistence(timeout:3))
        XCTAssertEqual(option.label,label)
        var swipes=0
        while !option.isHittable && swipes<6 { row.swipeLeft(); swipes+=1 }
        XCTAssertTrue(option.isHittable)
        option.tap()
        XCTAssertTrue(option.isSelected)
    }
    func testFilterAndClearDoNotReload() {
        launch();choose("manualRefund",label:"Manual after-sales")
        XCTAssertTrue(app.staticTexts["profile.orderFilter.empty"].waitForExistence(timeout:3))
        XCTAssertTrue(app.staticTexts["profile.orderFilter.emptyHint"].exists)
        let before=app.staticTexts["profile.orderFilter.fixture.listReads"].label
        app.buttons["profile.orderFilter.clear"].tap()
        XCTAssertTrue(app.buttons["profile.order.701"].exists)
        XCTAssertEqual(app.staticTexts["profile.orderFilter.fixture.listReads"].label,before)
    }
    func testRefunderRowOpensItsOriginalDetail() {
        launch();choose("refunded",label:"Refunded");app.buttons["profile.order.705"].tap()
        let name = app.descendants(matching: .any).matching(identifier: "profile.order.detail.name").firstMatch
        let nameExists = name.waitForExistence(timeout:5)
        if !nameExists { captureFirstFailure(expected: "refunded original detail name row") }
        XCTAssertTrue(nameExists)
        let title = name.value as? String
        if title != "Synthetic refunded" { captureFirstFailure(expected: "original detail title value Synthetic refunded") }
        XCTAssertEqual(title, "Synthetic refunded")
        let detailReads = app.staticTexts["profile.orderFilter.fixture.detailReads"].label
        if detailReads != "1" { captureFirstFailure(expected: "exactly one original detail read") }
        XCTAssertEqual(detailReads,"1")
    }
    func testTrueEmptyIsNotFilteredEmpty() {
        launch(empty:true);XCTAssertTrue(app.staticTexts["profile.orders.empty"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["profile.orderFilter.empty"].exists)
    }
    func testRevocationHidesLoadedList() {
        launch();XCTAssertTrue(app.buttons["profile.order.701"].waitForExistence(timeout:5))
        app.buttons["profile.orderFilter.fixture.revoke"].tap()
        let unavailable = app.descendants(matching: .any).matching(identifier: "profile.orders.unavailable").firstMatch
        let unavailableExists = unavailable.waitForExistence(timeout:5)
        if !unavailableExists { captureFirstFailure(expected: "revoked orders unavailable") }
        XCTAssertTrue(unavailableExists)
        let pickerExists = app.descendants(matching: .any).matching(identifier: "profile.orderFilter.picker").firstMatch.exists
            || app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.orderFilter.chip.")).count != 0
        let rowCount = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.order.")).count
        if pickerExists || rowCount != 0 { captureFirstFailure(expected: "revoked order rows and picker absent") }
        XCTAssertFalse(pickerExists)
        XCTAssertEqual(rowCount, 0)
    }
    func testAccountSwitchRemovesPreviousRows() {
        launch();choose("refunded",label:"Refunded");app.buttons["profile.orderFilter.fixture.switch"].tap()
        XCTAssertTrue(app.staticTexts["profile.orders.empty"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["profile.order.705"].exists)
    }
}
