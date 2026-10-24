import XCTest

/// QuestifyApp routes --im-expanded-fixture to a synthetic-only navigation host.
/// These tests do not enable a production writer or device provider.
final class IMExpandedUITests: XCTestCase {
    func testDirectMessageEmptySquareReturnsToSameTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--im-expanded-fixture", "message-empty"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["messaging.list.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["messaging.list.emptySquare"].exists)
        let tabs = app.segmentedControls["messaging.list.scope"]
        tabs.buttons.element(boundBy: 2).tap()
        let entry = app.buttons["messaging.list.emptySquare"]
        XCTAssertTrue(entry.waitForExistence(timeout: 2))
        entry.tap()
        XCTAssertTrue(app.staticTexts["messaging.fixture.square"].waitForExistence(timeout: 2))
        app.buttons["messaging.fixture.square.close"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 2))
        XCTAssertTrue(tabs.buttons.element(boundBy: 2).isSelected)
        entry.tap()
        XCTAssertTrue(app.staticTexts["messaging.fixture.square"].waitForExistence(timeout: 2))
    }
    func testMessageSearchMissDoesNotOfferEmptySquare() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--im-expanded-fixture", "message-empty"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["messaging.list.empty"].waitForExistence(timeout: 5))
        let tabs = app.segmentedControls["messaging.list.scope"]
        tabs.buttons.element(boundBy: 1).tap()
        XCTAssertFalse(app.buttons["messaging.list.emptySquare"].exists)
        tabs.buttons.element(boundBy: 2).tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("missing")
        XCTAssertFalse(app.buttons["messaging.list.emptySquare"].exists)
    }
    func testMessageFailureDoesNotOfferEmptySquare() throws {
        for scenario in ["error", "unauthorized", "unconfigured"] {
            let app = XCUIApplication()
            app.launchArguments = ["--im-expanded-fixture", "message-" + scenario]
            app.launch()
            let state = scenario == "error" ? "error" : scenario == "unauthorized" ? "signedOut" : "unconfigured"
            XCTAssertTrue(app.descendants(matching: .any)["messaging.list." + state].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["messaging.list.emptySquare"].exists)
            app.terminate()
        }
    }
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
