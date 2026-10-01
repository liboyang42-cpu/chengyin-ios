import XCTest

final class EntryFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure=false
        app=XCUIApplication()
        app.launchArguments=["--uitesting-reset-language","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
    }
    override func tearDownWithError() throws { app.terminate();app=nil }

    func testPlayerAndMerchantEntryCanBeClosedAndRepeated() {
        for identifier in ["welcome.player","welcome.merchant","welcome.player"] {
            let entry=app.buttons[identifier]
            XCTAssertTrue(entry.waitForExistence(timeout:10))
            entry.tap()
            XCTAssertTrue(app.navigationBars["Sign in"].waitForExistence(timeout:5))
            XCTAssertTrue(app.buttons["auth.signIn"].exists)
            XCTAssertFalse(app.buttons["auth.signIn"].isEnabled)
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["welcome.settings"].waitForExistence(timeout:5))
        }
    }

    func testUnconfiguredBuildCannotSubmitCredentials() {
        app.buttons["welcome.player"].tap()
        let username=app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout:5));username.tap();username.typeText("fixture-user")
        let password=app.secureTextFields["Password"]
        password.tap();password.typeText("fixture-password")
        XCTAssertFalse(app.buttons["auth.signIn"].isEnabled)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout:5))
    }

    func testChinesePreferenceSurvivesRelaunchAndSwitchesBack() {
        app.buttons["welcome.settings"].tap()
        let chinese=app.staticTexts["简体中文"].firstMatch
        XCTAssertTrue(chinese.waitForExistence(timeout:5));chinese.tap()
        let done=app.buttons["完成"]
        XCTAssertTrue(done.waitForExistence(timeout:5));done.tap()
        XCTAssertTrue(app.buttons["welcome.player"].label.contains("玩家注册"))
        app.terminate()
        app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.player"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["welcome.player"].label.contains("玩家注册"))
        app.buttons["welcome.settings"].tap()
        app.staticTexts["English"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout:5));app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["welcome.player"].label.contains("Register as a player"))
    }
}
