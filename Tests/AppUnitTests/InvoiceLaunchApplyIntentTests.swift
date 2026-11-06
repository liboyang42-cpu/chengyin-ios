import XCTest
import Foundation
@testable import Questify

/// Submit-tap input ownership only; no real invoice or permission is created.
@MainActor final class InvoiceLaunchApplyIntentTests: XCTestCase {
    func testSelectionClearedBeforeQueuedExecutionKeepsOriginalIDs() async {
        let revision = UUID()
        var selection: Set<Int64> = [9, 2, 4]
        let intent = InvoiceLaunchApplyIntent(titleID: 12, selected: selection, identityRevision: revision)
        selection.removeAll()
        var delivered: [Int64] = []
        let accepted = await intent.submit(currentRevision: revision) { title, orders in
            XCTAssertEqual(title, 12); delivered = orders; return true
        }
        XCTAssertTrue(accepted); XCTAssertEqual(delivered, [2, 4, 9]); XCTAssertTrue(selection.isEmpty)
    }
    func testNewSelectionAndTitleCannotChangeCapturedIntent() async {
        let revision = UUID()
        var title: Int64 = 12
        var selected: Set<Int64> = [1, 3]
        let intent = InvoiceLaunchApplyIntent(titleID: title, selected: selected, identityRevision: revision)
        title = 18; selected = [50]
        _ = await intent.submit(currentRevision: revision) { sentTitle, orders in
            XCTAssertEqual(sentTitle, 12); XCTAssertEqual(orders, [1, 3]); return true
        }
        XCTAssertEqual(title, 18); XCTAssertEqual(selected, [50])
    }
    func testChangedIdentityNeverInvokesOperation() async {
        let intent = InvoiceLaunchApplyIntent(titleID: 12, selected: [1], identityRevision: UUID())
        var calls = 0
        let accepted = await intent.submit(currentRevision: UUID()) { _, _ in calls += 1; return true }
        XCTAssertFalse(accepted); XCTAssertEqual(calls, 0)
    }
    func testOperationFailureIsReturnedWithoutRetryOrClaimingReceipt() async {
        let revision = UUID()
        let intent = InvoiceLaunchApplyIntent(titleID: 12, selected: [1], identityRevision: revision)
        var calls = 0
        let accepted = await intent.submit(currentRevision: revision) { _, _ in calls += 1; return false }
        XCTAssertFalse(accepted); XCTAssertEqual(calls, 1)
    }
}
