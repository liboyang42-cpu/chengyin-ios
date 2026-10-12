import XCTest

final class MerchantCityTemplateHandoffFlowTests: XCTestCase {
    private func launch(chinese: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--merchant-city-template-handoff-fixture", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); return app
    }
    func testConfigurationOpensFullEditorAndCannotReturnAnUnsavedID() {
        let app = launch()
        app.buttons["merchant.cityTemplate.configure"].tap()
        // Form is not guaranteed to be exposed as Other; the normal editor tests query its ID across types.
        let editors = app.descendants(matching: .any).matching(identifier: "merchant.operations.editor")
        let opened = editors.element.waitForExistence(timeout: 5)
        if !opened {
            print("QUESTIFY_CITY_TEMPLATE_EDITOR_AX_BEGIN\n\(app.debugDescription)\nQUESTIFY_CITY_TEMPLATE_EDITOR_AX_END")
            attachFixtureScreenshot(self, app: app, name: "City template editor after one configuration tap")
        }
        XCTAssertTrue(opened, app.debugDescription)
        XCTAssertEqual(editors.count, 1, app.debugDescription)
        XCTAssertTrue(app.buttons["merchant.cityTemplate.useSaved"].exists)
        XCTAssertFalse(app.buttons["merchant.cityTemplate.useSaved"].isEnabled)
    }
    func testCancelLeavesUnfinishedPlacementFieldsAndSelection() {
        let app = launch()
        let name = app.staticTexts["merchant.cityTemplate.fixture.name"].label
        let address = app.staticTexts["merchant.cityTemplate.fixture.address"].label
        app.buttons["merchant.cityTemplate.configure"].tap()
        XCTAssertTrue(app.buttons["merchant.cityTemplate.cancelEditor"].waitForExistence(timeout: 5))
        app.buttons["merchant.cityTemplate.cancelEditor"].tap()
        XCTAssertTrue(app.buttons["merchant.cityTemplate.configure"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["merchant.cityTemplate.fixture.name"].label, name)
        XCTAssertEqual(app.staticTexts["merchant.cityTemplate.fixture.address"].label, address)
        XCTAssertEqual(app.staticTexts["merchant.cityTemplate.fixture.selection"].label, "71")
    }
    func testChineseLargeTextKeepsEntryAndUnsavedBoundaryReachable() {
        let app = launch(chinese: true, large: true)
        let configure = app.buttons["merchant.cityTemplate.configure"]
        for _ in 0..<5 where !configure.isHittable { app.swipeUp() }
        XCTAssertTrue(configure.isHittable); configure.tap()
        let use = app.buttons["merchant.cityTemplate.useSaved"]
        XCTAssertTrue(use.waitForExistence(timeout: 5)); XCTAssertFalse(use.isEnabled)
        XCTAssertTrue(app.buttons["merchant.cityTemplate.cancelEditor"].exists)
    }
}
