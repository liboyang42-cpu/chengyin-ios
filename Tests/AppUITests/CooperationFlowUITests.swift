import XCTest

/// Requires the host app's --cooperation-flow-fixture branch (documented integration step).
final class CooperationFlowUITests: XCTestCase {
    func testSyntheticFinanceAndDormantReview() {
        let app = XCUIApplication()
        app.launchArguments += ["--cooperation-flow-fixture", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.otherElements["coopflow.workbench"].waitForExistence(timeout: 5))
        app.buttons["coopflow.route.coopflow.finance"].tap()
        app.buttons["coopflow.settlement.finance.8"].tap()
        XCTAssertTrue(app.staticTexts["Amount not confirmed"].exists)
        XCTAssertTrue(app.staticTexts["Pending settlement"].exists)
    }
    func testTemplatePreviewCannotSubmit() {
        let app = XCUIApplication()
        app.launchArguments += ["--cooperation-flow-fixture", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["coopflow.route.coopflow.templates"].tap()
        app.buttons["coopflow.row.0"].tap()
        app.buttons["Review template deletion"].tap()
        XCTAssertTrue(app.buttons["coopflow.submit.disabled"].exists)
        XCTAssertFalse(app.buttons["coopflow.submit.disabled"].isEnabled)
    }
}
