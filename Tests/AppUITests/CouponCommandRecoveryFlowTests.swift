import XCTest

/// Three full sealed-fixture launches; independently shardable (540s conservative method estimate).
/// No live service, issuance, or write retry. Keep every restart/NOT_FOUND assertion.
@MainActor final class CouponCommandRecoveryFlowTests: XCTestCase, CouponRuntimeJourney {
    var app: XCUIApplication!
    var chinese = false
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDownWithError() throws { attachFailureScreenshot(self, app: app); app?.terminate(); app = nil }
    func testV1ReadOnlyReceiptRecoveryAfterRestartAndNotFoundKeepsJournal() throws {
        let journal = UUID()
        launch("commandUnknown", journalID: journal); openCoupons(); enterDraft(); tap("couponManagement.confirm")
        assertUnknownEditorIssue()
        try closeEditor(); XCTAssertEqual(try evidence()["writes"] as? Int, 1); app.terminate()
        launch("commandNotFound", journalID: journal); openCoupons(); tap("couponManagement.recover")
        let checked = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            (availableEvidence()?["routes"] as? [String])?.contains("api/coupon/command-receipt") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [checked], timeout: 5), .completed)
        XCTAssertEqual(try evidence()["writes"] as? Int, 0); XCTAssertEqual(try evidence()["pending"] as? Bool, true); app.terminate()
        launch("commandReadOnly", journalID: journal); openCoupons(); tap("couponManagement.recover")
        let recovered = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in availableEvidence()?["pending"] as? Bool == false }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [recovered], timeout: 5), .completed)
        let record = try evidence(); XCTAssertEqual(record["writes"] as? Int, 0); XCTAssertEqual(record["violations"] as? [String], [])
        XCTAssertTrue((record["routes"] as? [String])?.contains("api/merchant/coop-profile") == true)
    }

    /// These notices are read, never tapped. Use the foreground editor and the native
    /// text visibility instead of the common helper's inferred navigation-bar viewport.
    private func assertUnknownEditorIssue(file: StaticString = #filePath, line: UInt = #line) {
        let expected = "The result is unknown. Resubmission is locked until the original outcome can be verified."
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
                guard label == expected else {
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
        XCTFail("Expected visible editor issue '\(expected)'; \(lastGeometry)", file: file, line: line)
    }
}
