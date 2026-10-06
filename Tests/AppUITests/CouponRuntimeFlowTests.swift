import XCTest

/// Normal root -> account -> merchant -> recruiting/marketing-home -> published coupons.
/// Recorder-only acceptance; never a real merchant/backend execution test.
@MainActor final class CouponRuntimeFlowTests: XCTestCase, CouponRuntimeJourney {
    var app: XCUIApplication!
    var chinese = false
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    func testNormalRootReadOnlyLeaseCannotConfirm() throws {
        launch("readOnly"); openCoupons(); enterDraft()
        let confirm = app.buttons["couponManagement.confirm"]; XCTAssertTrue(revealFixtureElement(confirm, in: app, requiresHittable: false)); XCTAssertFalse(confirm.isEnabled)
    }
    func testNormalRootExplicitCreateThenOwnedStop() throws {
        launch("ready"); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        let acknowledgement = app.staticTexts["couponManagement.notice.editor.readback"]
        XCTAssertTrue(revealFixtureElement(acknowledgement, in: app, towardTop: true, requiresHittable: false))
        XCTAssertEqual(acknowledgement.label, "Server acknowledged; current coupon record verified.")
        try closeEditor(expectedDirty: false)
        tap("couponManagement.definition.910"); tap("couponManagement.stop.review"); tap("couponManagement.confirm")
        let stoppedAcknowledgement = app.staticTexts["couponManagement.notice.detail.readback"]
        XCTAssertTrue(revealFixtureElement(stoppedAcknowledgement, in: app, towardTop: true, requiresHittable: false))
        XCTAssertFalse(app.buttons["couponManagement.stop.review"].exists)
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            availableEvidence()?["writes"] as? Int == 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 5), .completed)
        let record = try evidence(), routes = try XCTUnwrap(record["routes"] as? [String])
        XCTAssertEqual(record["writes"] as? Int, 2); XCTAssertEqual(record["violations"] as? [String], [])
        XCTAssertEqual(record["pendingBeforeWrites"] as? [Bool], [true, true])
        let dates = try XCTUnwrap(record["publishedDates"] as? [String])
        XCTAssertEqual(dates.count, 2)
        for date in dates { XCTAssertNotNil(date.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression)) }
        XCTAssertTrue(routes.contains("api/merchant/marketing-home")); XCTAssertTrue(routes.contains("api/merchant/access/me"))
        XCTAssertFalse(routes.contains { $0.contains("subscription") || $0.contains("claim") || $0.contains("issue") })
    }
    func testNormalRootTimeoutCannotRepeatConfirmedPublication() throws {
        launch("unknown"); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        assertEditorIssue(.unknownOutcome)
        tap("couponManagement.publish.review")
        XCTAssertFalse(app.buttons["couponManagement.confirm"].exists)
        try closeEditor()
        let record = try evidence()
        XCTAssertEqual(record["writes"] as? Int, 1); XCTAssertEqual(record["pending"] as? Bool, true)
        XCTAssertEqual(record["pendingBeforeWrites"] as? [Bool], [true])
    }
    func testNormalRootFreshPermissionRevokedAtConfirmDoesNotWrite() throws {
        launch("revokeOnConfirm"); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        assertEditorIssue(.forbidden)
        try closeEditor()
        let record = try evidence()
        XCTAssertEqual(record["writes"] as? Int, 0)
        XCTAssertEqual(record["couponAccessReads"] as? Int, 2)
        XCTAssertEqual(record["pending"] as? Bool, false)
    }
    func testNormalRootDiskRestartDoesNotRedispatchUnknownCreation() throws {
        let journal = UUID()
        launch("unknown", journalID: journal); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        assertEditorIssue(.unknownOutcome)
        try closeEditor()
        XCTAssertEqual(try evidence()["writes"] as? Int, 1)
        app.terminate()
        launch("ready", journalID: journal); openCoupons(); enterDraft(expectReview: false)
        // preparePublish finds the original durable publish lock before asking for permission.
        assertEditorIssue(.unknownOutcome)
        XCTAssertFalse(app.buttons["couponManagement.confirm"].exists)
        try closeEditor()
        let record = try evidence()
        XCTAssertEqual(record["writes"] as? Int, 0)
        XCTAssertEqual(record["pending"] as? Bool, true)
        XCTAssertEqual(record["violations"] as? [String], [])
    }


    private enum EditorIssue: String {
        case unknownOutcome = "The result is unknown. Resubmission is locked until the original outcome can be verified."
        case forbidden = "This action is not available for the current account or coupon"
    }
    /// These notices are read, never tapped. Use the foreground editor and the native
    /// text visibility instead of the common helper's inferred navigation-bar viewport.
    private func assertEditorIssue(_ expected: EditorIssue, file: StaticString = #filePath, line: UInt = #line) {
        let notices = app.staticTexts.matching(identifier: "couponManagement.notice.editor.issue")
        var lastGeometry = "notice not yet present"
        for attempt in 0...10 {
            let editors = app.navigationBars.matching(identifier: "Create coupon")
            guard editors.count == 1 else {
                XCTFail("Expected one foreground Create coupon editor", file: file, line: line); return
            }
            let cancelLeaves = editors.element(boundBy: 0).buttons.matching(NSPredicate(format: "label == %@", "Cancel"))
                .allElementsBoundByIndex.filter { $0.descendants(matching: .button).count == 0 }
            guard cancelLeaves.count == 1, cancelLeaves[0].isHittable else {
                XCTFail("Create coupon editor is not in the foreground", file: file, line: line); return
            }
            let count = notices.count
            guard count <= 1 else {
                XCTFail("Expected one editor issue leaf, found \(count)", file: file, line: line); return
            }
            if count == 1 {
                let notice = notices.element(boundBy: 0), label = notice.label
                guard label == expected.rawValue else {
                    XCTFail("Unexpected editor issue: \(label)", file: file, line: line); return
                }
                let frame = notice.frame, appFrame = app.frame, hittable = notice.isHittable
                if !frame.isEmpty, appFrame.contains(frame), hittable { return }
                lastGeometry = "noticeFrame=\(frame), appFrame=\(appFrame), hittable=\(hittable)"
            }
            guard attempt < 10 else { break }
            // The notice is the editor's first section. Scroll only; never retry confirmation.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76)))
        }
        XCTFail("Expected visible editor issue '\(expected.rawValue)'; \(lastGeometry)", file: file, line: line)
    }
}
