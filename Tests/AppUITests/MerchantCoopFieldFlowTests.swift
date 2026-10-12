import XCTest

final class MerchantCoopFieldFlowTests: XCTestCase {
    private func launch(chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-merchant-operations-fixture", "--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)"]
        if chinese { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); tap("merchant.operations.entry.merchant.operations.cooperation", app); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let button = app.buttons[id]
        for _ in 0..<14 { if button.isHittable { break }; app.swipeUp() }
        for _ in 0..<18 { if button.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertTrue(button.isHittable); button.tap()
    }
    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        let value = (field.value as? String) ?? ""; field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count) + text)
    }
    func testTimeDirtyCancelKeepEditingAndApply() {
        let app = launch(); tap("merchant.coopField.open.availableTime", app)
        let field = app.textFields["merchant.coopField.input"]; replace(field, with: "Weekend afternoons")
        tap("merchant.coopField.cancel", app); tap("merchant.coopField.keepEditing", app)
        XCTAssertEqual(field.value as? String, "Weekend afternoons"); tap("merchant.coopField.apply", app)
        tap("merchant.coopField.open.availableTime", app); XCTAssertEqual(field.value as? String, "Weekend afternoons")
    }
    func testDemandDiscardDoesNotModifyExistingDraft() {
        let app = launch(); tap("merchant.coopField.open.demand", app)
        let field = app.textViews["merchant.coopField.input"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); let original = field.value as? String
        replace(field, with: "Discard this buffer"); tap("merchant.coopField.cancel", app); tap("merchant.coopField.discard", app)
        tap("merchant.coopField.open.demand", app); XCTAssertEqual(field.value as? String, original)
    }
    func testCapacityApplyUsesOriginalFullDraftReview() {
        let app = launch(); tap("merchant.coopField.open.capacity", app); replace(app.textFields["merchant.coopField.input"], with: "17")
        tap("merchant.coopField.apply", app); tap("merchant.operations.review", app)
        XCTAssertTrue(app.staticTexts["17"].waitForExistence(timeout: 5))
        // Review only: no confirm/save action is performed.
    }
    func testCleanCancelDoesNotAskToDiscard() {
        let app = launch(); tap("merchant.coopField.open.availableTime", app); tap("merchant.coopField.cancel", app)
        XCTAssertFalse(app.buttons["merchant.coopField.discard"].exists)
        XCTAssertTrue(app.buttons["merchant.coopField.open.availableTime"].exists)
    }
    func testChineseLargeTextKeepsThenDiscardsOnlyFieldInput() {
        let app = launch(chinese: true); tap("merchant.coopField.open.demand", app)
        replace(app.textViews["merchant.coopField.input"], with: "周末合作"); tap("merchant.coopField.cancel", app); tap("merchant.coopField.keepEditing", app)
        XCTAssertEqual(app.textViews["merchant.coopField.input"].value as? String, "周末合作")
        tap("merchant.coopField.cancel", app); tap("merchant.coopField.discard", app)
        XCTAssertTrue(app.buttons["merchant.coopField.open.demand"].exists)
    }
}
