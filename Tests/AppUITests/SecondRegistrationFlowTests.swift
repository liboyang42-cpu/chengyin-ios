import XCTest

final class SecondRegistrationFlowTests: XCTestCase {
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uitesting-reset-language", "--second-registration-fixture", scenario, "-AppleLanguages", "(en)"]
        app.launch(); return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    func testMatureRateZeroDenominatorAndImmatureCohortStaySeparate() {
        let app = launch("mature")
        XCTAssertTrue(element("secondRegistration.content", app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["7.5% (3 / 40)"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.staticTexts["No mature sample"].exists)
        XCTAssertFalse(app.staticTexts["0.0% (0 / 0)"].exists)
        XCTAssertTrue(app.staticTexts["Not mature · 5 observed so far"].exists)
    }
    func testMissingReportShowsExplicitUnavailableState() {
        let app = launch("unavailable")
        XCTAssertTrue(element("secondRegistration.unavailable", app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No mature sample"].exists)
    }
}
