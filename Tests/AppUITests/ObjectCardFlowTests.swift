import XCTest

/// Requires documented host fixture registration. These cases make no network requests.
final class ObjectCardFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false; app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "objectCards"]
        app.launch()
    }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app.terminate(); app = nil }
    private func selectCategory(_ index: Int, label: String) {
        // SwiftUI Menu is a PopUpButton on newer runtimes, a Button on older ones.
        let filter = app.descendants(matching: .any)["objects.filter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(filter.isHittable); XCTAssertTrue(filter.isEnabled)
        filter.tap()
        let category = app.buttons["objects.category.objects.category.\(index)"]
        XCTAssertTrue(category.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(category.label, label)
        category.tap()
    }
    func testCollectionCapAndAccessibleFrames() {
        let row = app.buttons["objects.card.901"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Showing up to the latest 40 cards per category"].exists)
        row.tap()
        let next = app.buttons["objects.frame.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].exists)
        app.buttons["objects.frame.previous"].tap()
        XCTAssertTrue(app.staticTexts["1 / 2"].exists)
        XCTAssertTrue(app.staticTexts["Image loading is not enabled"].exists)
    }
    func testFilterFailureDoesNotReplaceLoadedCards() {
        XCTAssertTrue(app.buttons["objects.card.901"].waitForExistence(timeout: 5))
        app.buttons["objects.fixture.fail"].tap()
        selectCategory(5, label: "Books and stationery")
        XCTAssertTrue(app.staticTexts["objects.failed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["objects.card.901"].exists)
    }
    func testSessionChangeAndEmptyCategory() {
        app.buttons["objects.fixture.session"].tap()
        XCTAssertTrue(app.buttons["objects.card.901"].waitForExistence(timeout: 5))
        selectCategory(4, label: "Food and drinks")
        XCTAssertTrue(app.staticTexts["objects.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["objects.card.901"].exists)
    }
}
