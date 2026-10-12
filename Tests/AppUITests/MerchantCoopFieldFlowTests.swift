import XCTest

final class MerchantCoopFieldFlowTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() {
        if let app = runningApp, (testRun?.totalFailureCount ?? 0) > 0 {
            print("QUESTIFY_MERCHANT_FIELD_AX_BEGIN\n\(app.debugDescription)\nQUESTIFY_MERCHANT_FIELD_AX_END")
        }
        attachFailureScreenshot(self, app: runningApp)
        runningApp?.terminate(); runningApp = nil; super.tearDown()
    }
    private func alertAction(_ id: String, in app: XCUIApplication) {
        let query = app.alerts.buttons.matching(identifier: id)
        func leaves() -> [XCUIElement] {
            query.allElementsBoundByIndex.filter {
                $0.descendants(matching: .button).count == 0 && $0.isEnabled && $0.isHittable
            }
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in leaves().count == 1 }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed, let action = leaves().first else {
            XCTFail("Expected one native alert action: " + app.debugDescription); return
        }
        XCTAssertTrue(action.exists); XCTAssertTrue(action.isHittable); XCTAssertTrue(action.isEnabled)
        action.tap()
    }
    private func replaceAll(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        guard let app = runningApp else { XCTFail("Missing fixture app"); return }
        field.tap()
        if let previous = field.value as? String, !previous.isEmpty, previous != field.placeholderValue {
            // A tap can leave the caret at the start of a TextEditor. Select the entire
            // native buffer instead of assuming that backspace starts at its end.
            field.press(forDuration: 1.1)
            let query = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Select All", "全选"]))
            func actions() -> [XCUIElement] {
                query.allElementsBoundByIndex.filter {
                    ($0.elementType == .button || $0.elementType == .menuItem) &&
                        $0.descendants(matching: .button).count == 0 && $0.isEnabled && $0.isHittable
                }
            }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in actions().count == 1 }, object: nil)
            guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed, let selectAll = actions().first else {
                XCTFail("Expected one native Select All action: " + app.debugDescription); return
            }
            selectAll.tap()
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "The full local buffer must be replaced before apply/cancel")
    }

    private func launch(chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-merchant-operations-fixture", "--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)"]
        if chinese { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        runningApp = app; app.launch(); tap("merchant.operations.entry.merchant.operations.cooperation", app); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        if id == "merchant.coopField.keepEditing" || id == "merchant.coopField.discard" { alertAction(id, in: app); return }
        let button = app.buttons[id]
        for _ in 0..<14 { if button.isHittable { break }; app.swipeUp() }
        for _ in 0..<18 { if button.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertTrue(button.isHittable); button.tap()
    }
    private func replace(_ field: XCUIElement, with text: String) { replaceAll(field, with: text) }
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
