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
}
