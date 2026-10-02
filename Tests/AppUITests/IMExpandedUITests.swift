import XCTest

/// QuestifyApp routes --im-expanded-fixture to a synthetic-only navigation host.
/// These tests do not enable a production writer or device provider.
final class IMExpandedUITests: XCTestCase {
    func testDormantControlsHaveNoSendSideEffect() throws {
        let app = XCUIApplication(); app.launchArguments = ["--im-expanded-fixture", "dormant"]; app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["im.full.controls"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["im.full.confirm"].exists)
    }
    func testSyntheticRouteReviewIsExplicit() throws {
        let app = XCUIApplication(); app.launchArguments = ["--im-expanded-fixture", "route-review"]; app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["im.full.controls"].waitForExistence(timeout: 5))
        let confirm = app.buttons["im.full.confirm"]
        for _ in 0..<8 { if confirm.exists && confirm.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(confirm.exists, app.debugDescription)
        XCTAssertTrue(confirm.isHittable, app.debugDescription)
        XCTAssertTrue(confirm.isEnabled)
    }
}
