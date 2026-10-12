import XCTest

final class MerchantNPCFieldFlowTests: XCTestCase {
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
        runningApp = app; app.launch(); tap("merchant.operations.entry.merchant.operations.character", app); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        if id == "merchant.npcField.keepEditing" || id == "merchant.npcField.discard" { alertAction(id, in: app); return }
        let b = app.buttons[id]; for _ in 0..<14 { if b.isHittable { break }; app.swipeUp() }; for _ in 0..<18 { if b.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(b.waitForExistence(timeout:5)); XCTAssertTrue(b.isHittable); b.tap()
    }
    private func replace(_ field: XCUIElement, _ value: String) { replaceAll(field, with: value) }
    func testNameKeepThenApplyUsesSourceTrim() {
        let app = launch(); tap("merchant.npcField.open.name",app); let field = app.textFields["merchant.npcField.input"]; replace(field," Local guide ")
        tap("merchant.npcField.cancel",app); tap("merchant.npcField.keepEditing",app); XCTAssertEqual(field.value as? String," Local guide ")
        tap("merchant.npcField.apply",app); tap("merchant.npcField.open.name",app); XCTAssertEqual(field.value as? String,"Local guide")
    }
    func testGreetingDiscardKeepsOriginal() {
        let app = launch(); tap("merchant.npcField.open.greeting",app); let field = app.textFields["merchant.npcField.input"]; let original = field.value as? String
        replace(field,"Discard this greeting"); tap("merchant.npcField.cancel",app); tap("merchant.npcField.discard",app); tap("merchant.npcField.open.greeting",app); XCTAssertEqual(field.value as? String,original)
    }
    func testPersonaAndKnowledgeRemainIndependent() {
        let app = launch(); tap("merchant.npcField.open.persona",app); replace(app.textViews["merchant.npcField.input"],"A kind local guide"); tap("merchant.npcField.apply",app)
        tap("merchant.npcField.open.knowledge",app); tap("merchant.npcField.cancel",app); tap("merchant.npcField.open.persona",app); XCTAssertEqual(app.textViews["merchant.npcField.input"].value as? String,"A kind local guide")
    }
    func testAppliedKnowledgeReachesExistingReviewWithoutSending() {
        let app = launch(); tap("merchant.npcField.open.knowledge",app); replace(app.textViews["merchant.npcField.input"],"Local draft facts"); tap("merchant.npcField.apply",app); tap("merchant.operations.review",app)
        XCTAssertTrue(app.staticTexts["Local draft facts"].waitForExistence(timeout:5))
    }
    func testChineseLargeTextKeepAndDiscard() {
        let app = launch(chinese:true); tap("merchant.npcField.open.knowledge",app); replace(app.textViews["merchant.npcField.input"],"街角店铺资料")
        tap("merchant.npcField.cancel",app); tap("merchant.npcField.keepEditing",app); XCTAssertEqual(app.textViews["merchant.npcField.input"].value as? String,"街角店铺资料")
        tap("merchant.npcField.cancel",app); tap("merchant.npcField.discard",app); XCTAssertTrue(app.buttons["merchant.npcField.open.knowledge"].exists)
    }
}
