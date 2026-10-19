import XCTest

/// w2-20 p2: chat route/signup cards read their display through the offline
/// TopicFixtureReader; location cards show a static map. Synthetic data only.
final class IMCardPreviewUITests: XCTestCase {
    private func open(_ scenario: String, message: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--im-expanded-fixture", "message-" + scenario]
        app.launch()
        let conversation = app.buttons["messaging.conversation.901"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 5)); conversation.tap()
        let row = app.buttons["messaging.message.\(message)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        return app
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) -> Bool {
        for _ in 0..<6 { if element.exists { return true }; app.swipeUp() }
        return element.waitForExistence(timeout: 2)
    }
    func testRouteCardShowsServerReadDisplay() {
        let app = open("cards", message: 14)
        XCTAssertTrue(reveal(app.descendants(matching: .any)["im.card.route.loaded"], app), app.debugDescription)
    }
    func testFailedRouteReadIsUnavailableNotRemoved() {
        let app = open("cardsUnavailable", message: 14)
        XCTAssertTrue(reveal(app.descendants(matching: .any)["im.card.route.unavailable"], app), app.debugDescription)
        XCTAssertTrue(app.buttons["im.card.route.retry"].exists)
    }
    func testLocationCardShowsStaticMap() {
        let app = open("cards", message: 15)
        XCTAssertTrue(reveal(app.descendants(matching: .any)["im.card.locationMap"], app), app.debugDescription)
    }
    func testReadOnlyFixtureHasNoRoutePreviewRead() {
        let app = open("success", message: 14)
        XCTAssertTrue(app.descendants(matching: .any)["messaging.message.detail"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["im.card.route.loaded"].exists)
    }
}
