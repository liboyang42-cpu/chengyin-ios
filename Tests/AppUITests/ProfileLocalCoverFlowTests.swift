import XCTest

/// Uses synthetic image injection, then the production preview/confirm/cancel UI.
/// Never opens or approves the system photo picker.
final class ProfileLocalCoverFlowTests: XCTestCase {
    private var capturedFirstFailure = false
    private func captureFirstFailure(_ app: XCUIApplication, expected: String) {
        guard !capturedFirstFailure else { return }
        capturedFirstFailure = true
        XCTContext.runActivity(named: "First local-cover failure: \(expected)") { activity in
            let prepare = app.buttons["profile.localCoverFixture.prepare"]
            let state = prepare.exists ? String(describing: prepare.value ?? "missing diagnostic value") : "prepare control absent"
            let detail = XCTAttachment(string: "Expected: \(expected)\nSynthetic preparation/lifecycle:\n\(state)")
            detail.name = "Local cover first-failure state"; detail.lifetime = .keepAlways; activity.add(detail)
            let firstFailureAX = app.debugDescription
            // The current CI exports stdout even when it does not export the xcresult bundle.
            print("LOCAL_COVER_FIRST_FAILURE expected=\(expected)\nSTATE:\n\(state)\nAX:\n\(firstFailureAX)")
            let hierarchy = XCTAttachment(string: firstFailureAX)
            hierarchy.name = "Local cover first-failure AX"; hierarchy.lifetime = .keepAlways; activity.add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Local cover first-failure screen"; screenshot.lifetime = .keepAlways; activity.add(screenshot)
        }
    }
    private func launch() -> XCUIApplication {
        let app=XCUIApplication(); app.launchArguments += ["--uitesting","--uitesting-profile-local-cover"]; app.launch(); return app
    }
    private func tap(_ key: String,_ app: XCUIApplication) {
        let b=app.buttons[key]; let exists=b.waitForExistence(timeout:3)
        if !exists { captureFirstFailure(app, expected: key) }
        XCTAssertTrue(exists); if !b.isHittable { app.swipeUp() }; b.tap()
    }
    func testCancelPreviewLeavesDefaultWithoutAnyWrites() {
        let app=launch(); tap("profile.localCoverFixture.prepare",app)
        let previewExists=app.images["profile.localCover.preview"].waitForExistence(timeout:3)
        if !previewExists { captureFirstFailure(app, expected: "profile.localCover.preview") }
        XCTAssertTrue(previewExists)
        tap("profile.localCover.close",app)
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.writes"].label,"Writes: 0")
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.state"].label,"Default")
    }
    func testConfirmCoverThenRereadFromStore() {
        let app=launch(); tap("profile.localCoverFixture.prepare",app); tap("profile.localCover.confirm",app)
        let previewExists=app.images["profile.localCover.preview"].waitForExistence(timeout:3)
        if !previewExists { captureFirstFailure(app, expected: "profile.localCover.preview") }
        XCTAssertTrue(previewExists)
        tap("profile.localCoverFixture.reload",app)
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.writes"].label,"Writes: 1")
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.state"].label,"Saved")
    }
    func testRestoreDefaultCanBeCancelledThenConfirmed() {
        let app=launch(); tap("profile.localCoverFixture.prepare",app); tap("profile.localCover.confirm",app)
        tap("profile.localCover.edit",app); tap("profile.localCover.restore",app); tap("profile.localCover.cancelReview",app)
        tap("profile.localCover.close",app)
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.writes"].label,"Writes: 1")
        tap("profile.localCover.edit",app); tap("profile.localCover.restore",app); tap("profile.localCover.confirm",app)
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.state"].label,"Default")
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.writes"].label,"Writes: 2")
    }
    func testSwitchAccountDoesNotDisplayFormerCover() {
        let app=launch(); tap("profile.localCoverFixture.prepare",app); tap("profile.localCover.confirm",app)
        tap("profile.localCoverFixture.switch",app)
        XCTAssertTrue(app.otherElements["profile.localCover.default"].waitForExistence(timeout:3))
        XCTAssertFalse(app.images["profile.localCover.preview"].exists)
    }
    func testSignedOutAccountCannotEditOrDisplayCover() {
        let app=launch(); tap("profile.localCoverFixture.prepare",app); tap("profile.localCover.confirm",app)
        tap("profile.localCoverFixture.logout",app)
        XCTAssertFalse(app.buttons["profile.localCover.edit"].exists); XCTAssertFalse(app.images["profile.localCover.preview"].exists)
    }
}


extension ProfileLocalCoverFlowTests {
    func testSinglePreparedEditorSurvivesParentUpdatesUntilExplicitClose() {
        let app = launch()
        tap("profile.localCoverFixture.prepare", app)
        let confirmExists = app.buttons["profile.localCover.confirm"].waitForExistence(timeout: 3)
        if !confirmExists { captureFirstFailure(app, expected: "profile.localCover.confirm") }
        XCTAssertTrue(confirmExists)
        tap("profile.localCover.close", app)
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.writes"].label, "Writes: 0")
        XCTAssertEqual(app.staticTexts["profile.localCoverFixture.state"].label, "Default")
        let trace = String(describing: app.buttons["profile.localCoverFixture.prepare"].value ?? "")
        let events = trace.split(separator: "\n").map(String.init)
        // One user open must not create multiple simultaneous editors for Section children.
        let creations = events.filter { $0.contains("nativePresenter[") && $0.contains("].make ") }
        XCTAssertEqual(creations.count, 1, trace)
        XCTAssertEqual(events.filter { $0.contains(" editor.appear ") }.count, 1, trace)
        let closeTap = events.firstIndex { $0.contains(" editor.close.tap ") }
        let firstClose = events.firstIndex { $0.contains(" model.close.begin ") }
        XCTAssertNotNil(closeTap, trace)
        XCTAssertNotNil(firstClose, trace)
        if let closeTap, let firstClose { XCTAssertLessThan(closeTap, firstClose, trace) }
    }
}
