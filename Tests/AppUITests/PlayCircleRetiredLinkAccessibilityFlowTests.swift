import XCTest

/// Existing synthetic host, unchanged missing-link resolution and real view callback.
final class PlayCircleRetiredLinkAccessibilityFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testMissingStateDoesNotOverwriteHomeActionIdentity() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "--uitesting-module", "playCircleLink",
            "--play-circle-link-query", "inviteCode=AB12", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); defer { app.terminate() }
        let home = app.buttons.matching(identifier: "playx.circleLink.home")
        XCTAssertTrue(home.element.waitForExistence(timeout: 10), app.debugDescription)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Synthetic missing circle link action identity"
        tree.lifetime = .keepAlways; add(tree)
        XCTAssertEqual(home.count, 1, app.debugDescription)
        XCTAssertEqual(home.element.label, "返回首页")
        XCTAssertTrue(home.element.isEnabled && home.element.isHittable)
        XCTAssertEqual(app.buttons.matching(identifier: "playx.circleLink.missing").count, 0)
        XCTAssertTrue(app.staticTexts["探索链接不完整"].exists)
        home.element.tap()
        XCTAssertTrue(app.staticTexts["playx.circleLink.fixtureHome"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["playx.circleLink.home"].exists)
    }
}
