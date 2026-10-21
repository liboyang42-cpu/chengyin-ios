import XCTest
@testable import QuestifyCore

final class ClubOpsJoinNotifyPresentationTests: XCTestCase {
    func testProgressLabelOnlyOnActingRowWhileSubmitting() {
        XCTAssertEqual(ClubOpsJoinRequestCopy.progressKey(.approve, submitting: true, actingAction: .approve, actingMemberID: 703, memberID: 703), "clubOpsJoin.approving")
        XCTAssertEqual(ClubOpsJoinRequestCopy.progressKey(.reject, submitting: true, actingAction: .reject, actingMemberID: 703, memberID: 703), "clubOpsJoin.rejecting")
        XCTAssertNil(ClubOpsJoinRequestCopy.progressKey(.approve, submitting: false, actingAction: .approve, actingMemberID: 703, memberID: 703))
        XCTAssertNil(ClubOpsJoinRequestCopy.progressKey(.approve, submitting: true, actingAction: .reject, actingMemberID: 703, memberID: 703))
        XCTAssertNil(ClubOpsJoinRequestCopy.progressKey(.approve, submitting: true, actingAction: .approve, actingMemberID: 704, memberID: 703))
        XCTAssertNil(ClubOpsJoinRequestCopy.progressKey(.approve, submitting: true, actingAction: nil, actingMemberID: nil, memberID: 703))
        XCTAssertNil(ClubOpsJoinRequestCopy.progressKey(.remove, submitting: true, actingAction: .remove, actingMemberID: 703, memberID: 703))
    }
    func testLoadIssueSeparatesFailureStaleAndDenial() {
        XCTAssertEqual(ClubOpsJoinRequestCopy.loadIssue(failed: true, denied: false, stale: false, hasSnapshot: false), .failed)
        XCTAssertEqual(ClubOpsJoinRequestCopy.loadIssue(failed: true, denied: false, stale: true, hasSnapshot: true), .stale)
        XCTAssertNil(ClubOpsJoinRequestCopy.loadIssue(failed: true, denied: true, stale: false, hasSnapshot: false))
        XCTAssertNil(ClubOpsJoinRequestCopy.loadIssue(failed: false, denied: false, stale: false, hasSnapshot: true))
        XCTAssertNil(ClubOpsJoinRequestCopy.loadIssue(failed: false, denied: false, stale: true, hasSnapshot: false))
        XCTAssertNil(ClubOpsJoinRequestCopy.loadIssue(failed: false, denied: false, stale: true, hasSnapshot: true))
    }
    func testNotifyFailureCopyUsesOwnTableAndLeavesDenialToNote() {
        let copy = ClubOpsPageFailureCopy(operation: .audienceCounts, failure: .malformed)
        XCTAssertEqual(copy?.table, "ClubOpsJoinNotify"); XCTAssertEqual(copy?.titleKey, "clubOpsNotify.failed")
        XCTAssertEqual(copy?.retryKey, "clubOpsNotify.retry")
        XCTAssertNil(ClubOpsPageFailureCopy(operation: .audienceCounts, failure: .forbidden))
    }
    func testDirectMerchantLedgerAndFailureClassifier() throws {
        let emptyLedger = try ClubDirectMerchantLedgerPresentation(value: .array([]))
        XCTAssertEqual(ClubDirectMerchantLedgerPresentation.sectionTitle, "商家计酬")
        XCTAssertTrue(emptyLedger.isEmpty)
        XCTAssertEqual(emptyLedger.emptyText, "暂无商家计酬记录")

        let ledger = try ClubDirectMerchantLedgerPresentation(value: .object([
            "rows": .array([
                .object([
                    "id": .integer(11),
                    "merchantName": .string(" 山野咖啡 "),
                    "amountText": .string("¥128.00"),
                    "status": .string("SETTLED")
                ]),
                .object([
                    "id": .integer(12),
                    "name": .string("星河露营"),
                    "settledAmountText": .string("¥64.50"),
                    "status": .string("PENDING")
                ])
            ])
        ]))
        XCTAssertFalse(ledger.isEmpty)
        XCTAssertNil(ledger.emptyText)
        XCTAssertEqual(ledger.rows, [
            try ClubDirectMerchantLedgerPresentation.Row(id: 11, merchantName: "山野咖啡", amountText: "¥128.00", statusLabel: "已入账"),
            try ClubDirectMerchantLedgerPresentation.Row(id: 12, merchantName: "星河露营", amountText: "¥64.50", statusLabel: "待结算")
        ])
        XCTAssertThrowsError(try ClubDirectMerchantLedgerPresentation(value: .array([
            .object(["id": .integer(1), "merchantName": .string("A"), "amountText": .string("¥1.00"), "status": .string("SETTLED")]),
            .object(["id": .integer(1), "merchantName": .string("B"), "amountText": .string("¥2.00"), "status": .string("SETTLED")])
        ])))

        XCTAssertEqual(ClubOpsNetworkFailureClassifier.classify(URLError(.notConnectedToInternet)), .network)
        XCTAssertEqual(ClubOpsNetworkFailureClassifier.title(for: .notify, error: URLError(.timedOut)), "网络连接失败")
        XCTAssertEqual(ClubOpsNetworkFailureClassifier.title(for: .joinRequests, error: URLError(.networkConnectionLost)), "网络连接失败")
        XCTAssertEqual(ClubOpsNetworkFailureClassifier.title(for: .notify, error: ClubGovernanceFailure.malformed), "通知工具暂时不可用")
        XCTAssertEqual(ClubOpsNetworkFailureClassifier.title(for: .joinRequests, error: ClubGovernanceFailure.malformed), "入会申请加载失败")

        let rowIssue = ClubJoinRequestRowIssuePresentation(memberID: 703, failedMemberID: 703, submitting: false)
        XCTAssertEqual(rowIssue?.title, "这次处理没有完成")
        XCTAssertEqual(rowIssue?.actionTitle, "重新核对")
        XCTAssertEqual(rowIssue?.replaysWrite, false)
        XCTAssertNil(ClubJoinRequestRowIssuePresentation(memberID: 703, failedMemberID: 703, submitting: true))
        XCTAssertNil(ClubJoinRequestRowIssuePresentation(memberID: 704, failedMemberID: 703, submitting: false))
    }
}
