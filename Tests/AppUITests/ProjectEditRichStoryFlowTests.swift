import XCTest

/// Authored synthetic UI coverage only. Apple simulator execution is NOT_RUN in Linux.
final class ProjectEditRichStoryFlowTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--uitesting-module", "projectEdit", "--project-edit-rich-story"]
        app.launch(); return app
    }
    private func find(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 { if element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    private func openAlbum(_ app: XCUIApplication) {
        let chapter = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "projectEdit.chapter.")).firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 5)); find(chapter, in: app); chapter.tap()
        let album = app.buttons["projectEdit.rich.block.rich-dream"]; find(album, in: app); album.tap()
        XCTAssertTrue(app.textFields["projectEdit.rich.albumTitle"].waitForExistence(timeout: 3))
    }
    func testRichAlbumEditAppearsInReviewAndCancellationDoesNotSubmit() {
        let app = launch(); openAlbum(app)
        let title = app.textFields["projectEdit.rich.albumTitle"]; title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Fixture album".count) + "Reviewed album")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        let review = app.buttons["projectEdit.review"]; find(review, in: app); review.tap()
        let edited = app.staticTexts["Reviewed album"]; find(edited, in: app)
        XCTAssertTrue(edited.exists)
        let cancel = app.buttons["projectEdit.cancelReview"]; find(cancel, in: app); cancel.tap()
        XCTAssertFalse(app.staticTexts["Simulation completed. No project was published."].exists)
    }
    func testSigningOutDismissesNestedRichEditor() {
        let app = launch(); openAlbum(app)
        app.buttons["projectEdit.fixture.signOut"].tap()
        XCTAssertTrue(app.staticTexts["projectEdit.signIn"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["projectEdit.rich.albumTitle"].exists)
    }
    func testDreamImageAdditionIsLocalAndDoesNotPublish() {
        let app = launch(); openAlbum(app)
        let add = app.buttons["projectEdit.rich.addImage"]; find(add, in: app); add.tap()
        XCTAssertTrue(app.textFields["projectEdit.rich.image.1"].exists)
        XCTAssertFalse(app.buttons["projectEdit.confirmLive"].exists)
    }
}
