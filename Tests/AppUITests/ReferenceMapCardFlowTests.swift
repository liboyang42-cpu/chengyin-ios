import XCTest

/// Authored synthetic evidence only. Accessibility audits and screenshots must be
/// executed on Apple CI; they do not prove live data, VoiceOver or provider acceptance.
final class ReferenceMapCardFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    func testFullBilingualCardTextAndMissingArtworkAtBothAppearancesAndSizes() {
        for chinese in [false, true] {
            for maximum in [false, true] {
                app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)",
                    "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-module", "searchMap", "--uitesting-search-map-entry", "cards"]
                if maximum { app.launchArguments += ["--uitesting-max-text", "--uitesting-dark", "--uitesting-reduce-motion"] }
                app.launch()
                let title = "A very long neighborhood discovery walk with the complete destination name · 城市街区探索漫步与完整目的地名称，重要信息保留到最后"
                XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
                XCTAssertTrue(app.descendants(matching: .any)["reference.card.missing"].exists)
                attachFixtureScreenshot(self, app: app, name: "Image card top \(chinese ? "Chinese" : "English") \(maximum ? "maximum dark" : "normal light")")
                app.swipeUp(); app.swipeUp()
                XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "不能省略最后一段")).firstMatch.exists)
                attachFixtureScreenshot(self, app: app, name: "Image card full subtitle \(chinese ? "Chinese" : "English") \(maximum ? "maximum" : "normal")")
                app.terminate()
            }
        }
    }
    func testCardAccessibilityAuditForNormalSyntheticFixture() throws {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "--uitesting-module", "searchMap", "--uitesting-search-map-entry", "cards"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["reference.card.missing"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.contrast, .textClipped, .sufficientElementDescription])
    }
}
