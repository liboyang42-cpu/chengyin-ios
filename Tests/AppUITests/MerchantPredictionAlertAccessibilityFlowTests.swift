import XCTest

/// Exercises the production alert in the existing sealed merchant fixture.
final class MerchantPredictionAlertAccessibilityFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testPendingAnnouncementHasOneSemanticElementAndNoDecorativeFocusStop() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US", "--uitesting-merchant-fixture", "owner"]
        app.launch()
        defer { app.terminate() }
        let matches = app.descendants(matching: .any).matching(identifier: "merchantOps.predict.workbenchAlert")
        for _ in 0..<8 {
            if matches.count > 0 { break }
            app.swipeUp()
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Synthetic prediction announcement accessibility"
        tree.lifetime = .keepAlways; add(tree)
        XCTAssertEqual(matches.count, 1, app.debugDescription)
        guard matches.count == 1 else { return }
        XCTAssertEqual(matches.element.label, "2 prediction rounds are waiting for your answer")
        XCTAssertEqual(app.images.matching(identifier: "merchantOps.predict.workbenchAlert").count, 0)
        XCTAssertFalse(matches.element.label.contains("questionmark.bubble"))
    }
}
