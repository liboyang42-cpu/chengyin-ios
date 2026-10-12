import XCTest

final class MerchantNPCFieldFlowTests: XCTestCase {
    private func launch(chinese: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting-merchant-operations-fixture", "--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)"]
        if chinese { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); tap("merchant.operations.entry.merchant.operations.character", app); return app
    }
    private func tap(_ id: String, _ app: XCUIApplication) {
        let b = app.buttons[id]; for _ in 0..<14 { if b.isHittable { break }; app.swipeUp() }; for _ in 0..<18 { if b.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(b.waitForExistence(timeout:5)); XCTAssertTrue(b.isHittable); b.tap()
    }
    private func replace(_ field: XCUIElement, _ value: String) {
        XCTAssertTrue(field.waitForExistence(timeout:5)); field.tap(); let old = (field.value as? String) ?? ""
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+value)
    }
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
