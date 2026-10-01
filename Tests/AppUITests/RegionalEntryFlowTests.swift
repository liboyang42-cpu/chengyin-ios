import XCTest

final class RegionalEntryFlowTests:XCTestCase {
    private var app:XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure=false;app=XCUIApplication() }
    override func tearDownWithError() throws { app.terminate();app=nil }
    private func launch(_ market:String,first:Bool=true) {
        app.launchArguments=["--uitesting-market",market,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        if first { app.launchArguments.append("--uitesting-first-launch-language") }
        app.launch()
        XCTAssertTrue(app.buttons["welcome.settings"].waitForExistence(timeout:15),app.debugDescription)
    }
    func testChinaDefaultsChineseAndLanguagePersistsWithoutChangingMarket() {
        launch("CN")
        XCTAssertTrue(app.staticTexts["让城市成为下一场冒险"].waitForExistence(timeout:5),app.debugDescription)
        app.buttons["welcome.settings"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["region.market.value"].label,"CN")
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["region.market.value"].label,"CN")
        app.buttons["Done"].tap();app.terminate()
        launch("CN",first:false)
        XCTAssertTrue(app.staticTexts["Make the city your next adventure"].waitForExistence(timeout:5))
    }
    func testUSDefaultsEnglishAndCannotUseChinaCredentialForms() {
        launch("US")
        XCTAssertTrue(app.staticTexts["Make the city your next adventure"].waitForExistence(timeout:5))
        app.buttons["welcome.player"].tap()
        XCTAssertTrue(app.navigationBars["Sign in"].waitForExistence(timeout:5))
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["region.auth.pending"].exists)
        app.buttons["auth.otherChannels"].tap()
        XCTAssertTrue(app.navigationBars["More ways to sign in"].waitForExistence(timeout:5))
        XCTAssertFalse(app.textFields["auth.channels.phone"].exists)
        XCTAssertFalse(app.buttons["auth.channels.sendCode"].exists)
        XCTAssertFalse(app.buttons["auth.channels.appleSignIn"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="US login contract pending – no China credential form";shot.lifetime = .keepAlways;add(shot)
    }
}
