import XCTest

final class PlayPreferenceFlowTests:XCTestCase {
    private func launch()->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--uitesting-module","playExperience","--uitesting-play-experience-scenario","preference","-AppleLanguages","(en)","-AppleLocale","en_US"];app.launch();return app
    }
    func testPreferenceUsesSourceQuestionAndNativePicker() {
        let app=launch(),node=app.buttons["playx.node.701"]
        XCTAssertTrue(node.waitForExistence(timeout:5));node.tap()
        let link=app.buttons["Preference questionnaire"];XCTAssertTrue(link.waitForExistence(timeout:3));link.tap()
        XCTAssertTrue(app.staticTexts["Synthetic preference question"].waitForExistence(timeout:3))
        XCTAssertTrue(app.buttons["playx.preference.step.FIRST"].exists || app.otherElements["playx.preference.step.FIRST"].exists)
    }
    func testOperatingSummaryIsSeparatePrivateDestination() {
        let app=launch();let link=app.buttons["New-life summary"]
        for _ in 0..<8 {if link.exists && link.isHittable {break};app.swipeUp()}
        XCTAssertTrue(link.exists);link.tap()
        XCTAssertTrue(app.staticTexts["Private build. Only visible to you."].waitForExistence(timeout:3))
        XCTAssertTrue(app.staticTexts["Synthetic tag"].exists)
    }
}
