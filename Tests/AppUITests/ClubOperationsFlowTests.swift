import XCTest

/// Authored offline scenarios. These are not backend or permission-change acceptance.
final class ClubOperationsFlowTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    override func tearDownWithError() throws {
        attachFailureScreenshot(self, app: app)
        if (testRun?.totalFailureCount ?? 0) > 0 {
            let evidence = XCTAttachment(string: app.debugDescription)
            evidence.name = "Club operations failure accessibility hierarchy"; evidence.lifetime = .keepAlways; add(evidence)
        }
        app.terminate(); app = nil
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    // The toolbar wrapper may retain an earlier accessibilityValue after a scope change.
    // Read the Text leaf that displays the live fixture store's count and identity.
    private var visibleWriteCounters: [XCUIElement] {
        func visible(_ elements: [XCUIElement]) -> [XCUIElement] {
            elements.filter { $0.exists && $0.isHittable && !$0.frame.isEmpty && app.frame.contains($0.frame) }
        }
        // Run108 exposes both the covered root List and the foreground sheet's
        // counter. Resolve the leaf through its actual toolbar, never the covered
        // root or the stale accessibility value cached on a wrapping Other node.
        let presented = app.toolbars.staticTexts.matching(identifier: "club.ops.writeCount")
        if presented.count > 0 { return visible(presented.allElementsBoundByIndex) }
        return visible(app.staticTexts.matching(identifier: "club.ops.writeCount").allElementsBoundByIndex)
    }
    private var writeCounter: XCUIElement {
        let counters = visibleWriteCounters
        XCTAssertEqual(counters.count, 1, app.debugDescription)
        return counters.first ?? app.staticTexts["club.ops.writeCount"].firstMatch
    }
    private func launch(_ scenario: String = "owner", chinese: Bool = false) {
        app.launchArguments = ["--uitesting-reset-language", "-AppleLanguages", chinese ? "(zh-Hans)" : "(en)", "-AppleLocale", chinese ? "zh_CN" : "en_US", "--uitesting-club-operations", scenario]
        app.launch(); XCTAssertTrue(element("club.ops.fixtureNotice").waitForExistence(timeout: 10))
    }
    private var emittedPresentationFailure = false
    private func emitPresentationFailure(_ phase: String, scopedReadiness: [String: Bool] = [:]) {
        guard !emittedPresentationFailure else { return }
        emittedPresentationFailure = true
        // Only this offline fixture's fixed counters/controls. stdout is retained
        // even when the runner does not export the xcresult screenshot attachments.
        let notice = app.staticTexts["club.ops.fixtureNotice"].firstMatch
        var presentation = "absent"
        if notice.exists { presentation = (notice.value as? String) ?? "unavailable" }
        let controls = ["club.ops.openCreate", "club.ops.openManage", "club.ops.reviewProfile", "club.ops.setting.publicVisible", "club.ops.confirm", "club.ops.close"]
        let rows: [[String: Any]] = controls.map { id in
            let control = app.buttons.matching(identifier: id).allElementsBoundByIndex
                .reversed().first(where: { $0.exists && $0.isHittable }) ?? app.buttons[id].firstMatch
            return ["id": id, "exists": control.exists, "hittable": control.exists && control.isHittable,
                    "frame": control.exists ? String(describing: control.frame) : "absent"]
        }
        let payload: [String: Any] = ["version": 1, "fixture": "club-operations", "phase": phase,
            "presentation": presentation,
            "reviewExists": element("club.ops.reviewSheet").exists,
            "workspaceExists": element("club.ops.fixture.workspace").exists,
            "profileFieldExists": element("club.ops.field.name").exists,
            "scopedReadiness": scopedReadiness, "controls": rows]
        if let bytes = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let message = String(data: bytes, encoding: .utf8) {
            print("QUESTIFY_CLUB_PRESENTATION_EVIDENCE_V1 " + message)
            fflush(stdout)
        }
        attachFixtureScreenshot(self, app: app, name: "Club presentation before further gestures")
    }
    private func tap(_ id: String) {
        if id.hasPrefix("club.ops.setting.") {
            // A partially exposed List row can report isHittable while its
            // center is under the foreground bottom toolbar. Reveal the whole
            // row using the existing bar/keyboard-aware viewport before tapping.
            let setting = app.buttons.matching(identifier: id).firstMatch
            guard revealFixtureElement(setting, in: app), setting.exists,
                  setting.isHittable, setting.isEnabled else {
                emitPresentationFailure("setting-not-clear-of-bars:" + id)
                XCTFail("Setting row is not fully exposed: " + app.debugDescription); return
            }
            setting.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }
        _ = reveal(id)
        let buttons = app.buttons.matching(identifier: id)
        guard let control = buttons.allElementsBoundByIndex.reversed().first(where: { $0.exists && $0.isHittable }) else {
            emitPresentationFailure("missing-button:" + id)
            XCTFail("Missing presented button: \(id). \(app.debugDescription)"); return
        }
        XCTAssertTrue(control.isEnabled, app.debugDescription); control.tap()
    }
    private func reveal(_ id: String) -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(identifier: id)
        func visible() -> XCUIElement? {
            matches.allElementsBoundByIndex.reversed().first { $0.exists && $0.isHittable }
        }
        for _ in 0..<14 { if let control = visible() { return control }; app.swipeUp() }
        for _ in 0..<14 { if let control = visible() { return control }; app.swipeDown() }
        return matches.firstMatch
    }
    private func count(_ value: Int) {
        // The covered root List and foreground sheet toolbar both mount this ID.
        // Re-resolve the unique foreground Text leaf for each existing-budget poll.
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let counters = self.visibleWriteCounters
            return counters.count == 1 && counters[0].label == String(value)
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed, app.debugDescription)
    }
    private func openCreateProfile() -> Bool {
        tap("club.ops.openCreate")
        // The name exists only after the create snapshot is rendered. Require
        // its exact workspace ancestor in one typed query, rather than two
        // global accessibility queries inside a block-predicate poll. Keep the
        // same five-second budget and never swipe/replay an unconfirmed entry.
        let workspace = app.collectionViews["club.ops.fixture.workspace"].firstMatch
        let name = workspace.textFields["club.ops.field.name"].firstMatch
        guard name.waitForExistence(timeout: 5) else {
            // One observation of these exact typed queries, without another
            // wait, action, or retry. Diagnostics may be later than the timeout.
            emitPresentationFailure("create-profile-missing-after-single-tap", scopedReadiness: [
                "readyWithinFiveSeconds": false,
                "workspaceExistsAfterTimeout": workspace.exists,
                "workspaceNameExistsAfterTimeout": name.exists
            ])
            XCTFail("Create workspace did not expose its profile name within five seconds. " + app.debugDescription); return false
        }
        return true
    }
    private func reviewSetting() {
        tap("club.ops.openManage"); tap("club.ops.setting.publicVisible")
        // A single tap must produce the actual review before looking/scrolling
        // for Confirm. Preserve the original business assertions in each case.
        guard element("club.ops.reviewSheet").waitForExistence(timeout: 5) else {
            emitPresentationFailure("review-missing-after-setting-tap")
            XCTFail("Setting tap did not present a review. " + app.debugDescription); return
        }
    }
    func testOwnerSettingRequiresReviewAndSingleConfirmation() {
        launch(); reviewSetting(); XCTAssertTrue(element("club.ops.reviewSheet").waitForExistence(timeout: 5))
        tap("club.ops.confirm"); count(1)
        XCTAssertTrue(reveal("club.ops.acknowledged").exists)
    }
    func testCancelReviewSendsNothing() {
        launch(); reviewSetting(); tap("club.ops.cancelReview"); count(0)
    }
    func testUnknownReadbackDoesNotUnlockAndReopenDoesNotReplay() {
        launch("unknown"); reviewSetting(); tap("club.ops.confirm"); count(1)
        tap("club.ops.readBack"); XCTAssertTrue(reveal("club.ops.outcomeUnknown").exists)
        XCTAssertFalse(element("club.ops.acknowledged").exists); count(1)
        tap("club.ops.close"); app.buttons["Leave form"].tap(); tap("club.ops.openManage")
        XCTAssertTrue(reveal("club.ops.outcomeUnknown").exists); count(1)
        _ = reveal("club.ops.setting.publicVisible")
        let setting = app.buttons["club.ops.setting.publicVisible"].firstMatch
        XCTAssertTrue(setting.exists); XCTAssertFalse(setting.isEnabled)
    }
    func testAdminProfileHasNoOwnerSettingsOrRoleActions() {
        launch("admin"); tap("club.ops.openManage")
        XCTAssertTrue(element("club.ops.field.name").waitForExistence(timeout: 5),
            "CLUB_OPS_SYNTHETIC_PRESENTATION " + String(describing: element("club.ops.fixtureNotice").value ?? "unavailable"))
        XCTAssertFalse(element("club.ops.setting.publicVisible").exists); XCTAssertFalse(element("club.ops.member.704").exists)
        XCTAssertTrue(reveal("club.ops.reviewProfile").exists)
        for id in ["club.ops.prioritySignup", "club.ops.field.quota", "club.ops.joinPolicy"] {
            XCTAssertFalse(element(id).exists, app.debugDescription)
        }
    }
    func testOrdinaryViewerIsDeniedAndCreateRoleGated() {
        launch("ordinary"); tap("club.ops.openManage"); XCTAssertTrue(reveal("club.ops.error").exists); count(0)
        tap("club.ops.close"); tap("club.ops.openCreate")
        XCTAssertFalse(element("club.ops.reviewProfile").exists)
    }
    func testTwoClubLimitPreventsCreateForm() {
        launch("limit"); tap("club.ops.openCreate")
        XCTAssertTrue(app.staticTexts["You already own two clubs. Manage an existing club instead."].waitForExistence(timeout: 5))
        XCTAssertFalse(element("club.ops.reviewProfile").exists); count(0)
    }
    func testUnverifiedReviewContainsNoSubmitControl() {
        launch("unverified"); reviewSetting()
        XCTAssertTrue(element("club.ops.reviewSheet").waitForExistence(timeout: 5)); XCTAssertFalse(element("club.ops.confirm").exists)
    }
    func testPopulatedMemberQuotaKeepsItsVisibleLabelInBothLanguages() {
        for chinese in [false, true] {
            launch(chinese: chinese); tap("club.ops.openManage")
            let field = element("club.ops.field.quota")
            XCTAssertTrue(revealFixtureElement(field, in: app), app.debugDescription)
            XCTAssertEqual(field.value as? String, "4")
            let label = app.staticTexts["clubQuota.visibleLabel"]
            XCTAssertTrue(label.exists, app.debugDescription)
            XCTAssertEqual(label.label, chinese ? "成员保留名额" : "Reserved member places")
            count(0)
            attachFixtureScreenshot(self, app: app, name: chinese ? "Populated member quota Chinese" : "Populated member quota English")
            app.terminate()
        }
    }
    func testMemberRoleConfirmationIdentifiesTarget() {
        launch(); tap("club.ops.openManage")
        let member = app.buttons["club.ops.member.704"].firstMatch
        func clearOfBottomToolbar() -> Bool {
            guard member.exists && member.isHittable else { return false }
            let topOfToolbar = app.toolbars.allElementsBoundByIndex
                .filter { $0.exists && $0.frame.minY > app.frame.midY }
                .map { $0.frame.minY }.min() ?? app.frame.maxY
            return member.frame.maxY < topOfToolbar
        }
        for _ in 0..<10 { if clearOfBottomToolbar() { break }; app.swipeUp() }
        XCTAssertTrue(clearOfBottomToolbar(), app.debugDescription)
        tap("club.ops.member.704")
        XCTAssertTrue(element("club.ops.reviewSheet").waitForExistence(timeout: 5), app.debugDescription)
        // LabeledContent exposes a combined localized label and value.
        let target = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Fixture member (#704)")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), app.debugDescription)
        tap("club.ops.confirm"); count(1)
    }
    func testChineseProfileValidationAndDiscard() {
        launch(chinese: true)
        guard openCreateProfile() else { return }
        tap("club.ops.reviewProfile")
        XCTAssertTrue(reveal("club.ops.error").exists); count(0)
        let name = element("club.ops.field.name"); app.swipeDown(); name.tap(); name.typeText("本地社群")
        tap("club.ops.close"); app.buttons["离开表单"].tap()
        XCTAssertTrue(element("club.ops.fixtureNotice").exists)
    }
    func testAccountSwitchDuringDelayedWriteKeepsOldOutcomeHidden() {
        launch("delayed"); reviewSetting(); tap("club.ops.confirm"); count(1)
        XCTAssertEqual(writeCounter.value as? String, "account=701;finished=0")
        tap("club.ops.switchAccount")
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let counters = self.visibleWriteCounters
            return counters.count == 1 && counters[0].value as? String == "account=702;finished=1"
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 5), .completed, app.debugDescription)
        XCTAssertTrue(element("club.ops.field.name").waitForExistence(timeout: 5))
        XCTAssertFalse(element("club.ops.acknowledged").exists); count(1)
        tap("club.ops.switchAccount")
        XCTAssertTrue(reveal("club.ops.outcomeUnknown").exists); count(1)
    }
}
