import XCTest

final class MerchantStoreFieldFlowTests: XCTestCase {
    private func launch(_ destination:String="profile", chinese:Bool=false) -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--uitesting-merchant-operations-fixture","--uitesting-reset-language","-AppleLanguages",chinese ? "(zh-Hans)" : "(en)"]
        if chinese {app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]}
        app.launch();tap("merchant.operations.entry.merchant.operations."+destination,app);return app
    }
    private func tap(_ id:String,_ app:XCUIApplication) {
        let button=app.buttons[id];for _ in 0..<14 {if button.isHittable {break};app.swipeUp()};for _ in 0..<18 {if button.isHittable {break};app.swipeDown()}
        XCTAssertTrue(button.waitForExistence(timeout:5));XCTAssertTrue(button.isHittable);button.tap()
    }
    private func replace(_ field:XCUIElement,_ text:String) {
        XCTAssertTrue(field.waitForExistence(timeout:5));field.tap();let current=(field.value as? String) ?? ""
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:current.count)+text)
    }
    func testNameCancelKeepThenApply() {
        let app=launch();tap("merchant.storeField.open.name",app);let field=app.textFields["merchant.storeField.input"];replace(field,"New local shop")
        tap("merchant.storeField.cancel",app);tap("merchant.storeField.keepEditing",app);XCTAssertEqual(field.value as? String,"New local shop")
        tap("merchant.storeField.apply",app);tap("merchant.storeField.open.name",app);XCTAssertEqual(field.value as? String,"New local shop")
    }
    func testBenefitsDiscardKeepsOriginal() {
        let app=launch();tap("merchant.storeField.open.derivativeBenefits",app);let field=app.textFields["merchant.storeField.input"];let original=field.value as? String
        replace(field,"Discard this field");tap("merchant.storeField.cancel",app);tap("merchant.storeField.discard",app);tap("merchant.storeField.open.derivativeBenefits",app);XCTAssertEqual(field.value as? String,original)
    }
    func testDecorRoleAndSloganHaveIndependentBuffers() {
        let app=launch("decor");tap("merchant.storeField.open.cityRole",app);replace(app.textFields["merchant.storeField.input"],"Quiet local stop");tap("merchant.storeField.apply",app)
        tap("merchant.storeField.open.slogan",app);tap("merchant.storeField.cancel",app);tap("merchant.storeField.open.cityRole",app);XCTAssertEqual(app.textFields["merchant.storeField.input"].value as? String,"Quiet local stop")
    }
    func testStoryAppliesIntoExistingReviewWithoutSending() {
        let app=launch("story");tap("merchant.storeField.open.description",app);replace(app.textViews["merchant.storeField.input"],"Story prepared locally");tap("merchant.storeField.apply",app);tap("merchant.operations.review",app)
        XCTAssertTrue(app.staticTexts["Story prepared locally"].waitForExistence(timeout:5))
    }
    func testChineseLargeTextKeepsThenDiscards() {
        let app=launch(chinese:true);tap("merchant.storeField.open.description",app);replace(app.textViews["merchant.storeField.input"],"街角的品牌故事")
        tap("merchant.storeField.cancel",app);tap("merchant.storeField.keepEditing",app);XCTAssertEqual(app.textViews["merchant.storeField.input"].value as? String,"街角的品牌故事")
        tap("merchant.storeField.cancel",app);tap("merchant.storeField.discard",app);XCTAssertTrue(app.buttons["merchant.storeField.open.description"].exists)
    }
}
