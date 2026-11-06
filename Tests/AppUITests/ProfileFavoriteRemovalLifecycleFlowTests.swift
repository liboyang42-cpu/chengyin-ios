import XCTest

/// Exercises the production entry/sheet/controller with the existing offline fixture.
/// Adds lifecycle evidence; does not alter its transport, grants, or original assertions.
final class ProfileFavoriteRemovalLifecycleFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }
    override func tearDownWithError() throws {
        preserve("final")
        app?.terminate()
        app = nil
    }
    private func preserve(_ stage: String) {
        guard let app else { return }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Favorite removal lifecycle - " + stage
        tree.lifetime = .keepAlways
        add(tree)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Favorite removal synthetic - " + stage
        shot.lifetime = .keepAlways
        add(shot)
    }
    private func launch() {
        app.launchArguments = ["--uitesting", "--uitesting-reset-language", "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US", "--uitesting-profile-favorite-removal",
            "--profile-favorite-removal-scenario", "success", "--uitesting-profile-favorite-removal-lifecycle"]
        app.launch()
    }
    private func openReview() {
        let entry = app.buttons["profile.favoriteRemoval.open.101"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(entry.isEnabled && entry.isHittable, app.debugDescription)
        preserve("before open")
        entry.tap()
        let confirm = app.buttons["profile.favoriteRemoval.confirm"]
        let ready = confirm.waitForExistence(timeout: 10)
        preserve("after open")
        XCTAssertTrue(ready, app.debugDescription)
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.close"].exists, app.debugDescription)
    }
    func testProductionEntryKeepsReviewMountedAndCancelReopensWithoutWriting() {
        launch()
        openReview()
        app.buttons["profile.favoriteRemoval.close"].tap()
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.open.101"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label, "Writes: 0")
        openReview()
        app.buttons["profile.favoriteRemoval.close"].tap()
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.open.101"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label, "Writes: 0")
    }
    func testBackgroundRetiresReviewAndRequiresFreshPresentationWithoutWriting() {
        launch()
        openReview()
        XCUIDevice.shared.press(.home)
        app.activate()
        preserve("after foreground")
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.open.101"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["profile.favoriteRemoval.confirm"].exists)
        XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label, "Writes: 0")
        openReview()
        app.buttons["profile.favoriteRemoval.close"].tap()
        XCTAssertTrue(app.buttons["profile.favoriteRemoval.open.101"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["profile.favoriteFixture.writes"].label, "Writes: 0")
    }
}
