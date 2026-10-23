import XCTest
@testable import QuestifyCore

final class ReviewResultVisibilityAdapterTests: XCTestCase {
    func testFirstJourneySubmitRejectReviseApprovePublicVisibleRecoverOriginal() throws {
        let flow = try ReviewResultVisibilityAdapter.flowSubmitRejectReviseApprove(
            submitRequestId: "rev-submit", submitTaskId: 1, submitterId: 9,
            rejectReason: "封面不合规", reviseRequestId: "rev-revise", reviseTaskId: 2)
        let submit = flow[0]
        let reject = flow[1]
        let revise = flow[2]
        let approve = flow[3]

        XCTAssertEqual(submit.taskStatus, ReviewResultVisibilityAdapter.Status.pending)
        XCTAssertEqual(ReviewResultVisibilityAdapter.Status.pending, 0)
        XCTAssertEqual(ReviewResultVisibilityAdapter.Status.approved, 1)
        XCTAssertEqual(ReviewResultVisibilityAdapter.Status.rejected, 2)
        XCTAssertEqual(ReviewResultVisibilityAdapter.Status.cancelled, 3)
        XCTAssertEqual(ReviewResultVisibilityAdapter.Status.escalated, 4)
        XCTAssertEqual(submit.recordAction, ReviewResultVisibilityAdapter.RecordAction.submit)
        XCTAssertFalse(
            ReviewResultVisibilityAdapter.visibility(submit, audience: .PUBLIC).publicVisible)
        XCTAssertTrue(
            ReviewResultVisibilityAdapter.visibility(submit, audience: .SUBMITTER).submitterVisible)

        XCTAssertEqual(reject.taskStatus, ReviewResultVisibilityAdapter.Status.rejected)
        XCTAssertTrue(
            ReviewResultVisibilityAdapter.visibility(reject, audience: .SUBMITTER).reviseAllowed)
        XCTAssertFalse(
            ReviewResultVisibilityAdapter.visibility(reject, audience: .PUBLIC).publicVisible)

        XCTAssertEqual(revise.requestId, "rev-revise")
        XCTAssertEqual(revise.taskStatus, ReviewResultVisibilityAdapter.Status.pending)

        XCTAssertEqual(approve.recordAction, ReviewResultVisibilityAdapter.RecordAction.approve)
        XCTAssertTrue(
            ReviewResultVisibilityAdapter.visibility(approve, audience: .PUBLIC).approvedResultVisible)
        XCTAssertTrue(
            ReviewResultVisibilityAdapter.visibility(approve, audience: .SUBMITTER).approvedResultVisible)
    }

    func testCurrentPublishedProjectionDoesNotTurnRejectedRequestIntoApprovedVisible() throws {
        let rejected = ReviewResultVisibilityAdapter.rejected(
            try ReviewResultVisibilityAdapter.submitted(requestId: "rev-old", taskId: 3, submitterId: 9),
            reasonText: "需修订")
        let publicView = ReviewResultVisibilityAdapter.visibilityForRequest(
            rejected, audience: .PUBLIC, currentContentProjectionPublished: true)
        XCTAssertFalse(publicView.publicVisible)
        XCTAssertFalse(publicView.approvedResultVisible)
        XCTAssertEqual(publicView.state, "REJECTED")
    }

    func testRejectedRoundCannotBeMarkedApproved() throws {
        let rejected = ReviewResultVisibilityAdapter.rejected(
            try ReviewResultVisibilityAdapter.submitted(requestId: "rev-old", taskId: 3, submitterId: 9),
            reasonText: "需修订")
        XCTAssertThrowsError(try ReviewResultVisibilityAdapter.approved(rejected))
    }

    func testMissingRequestIdStaysOptionalNone() throws {
        XCTAssertThrowsError(
            try ReviewResultVisibilityAdapter.submitted(requestId: "", taskId: 1, submitterId: 9))
        XCTAssertThrowsError(
            try ReviewResultVisibilityAdapter.submitted(requestId: nil, taskId: 1, submitterId: 9))
        let round = try ReviewResultVisibilityAdapter.submitted(
            requestId: "rev-ok", taskId: 1, submitterId: 9)
        XCTAssertEqual(round.requestId, "rev-ok")
        XCTAssertNotEqual(round.requestId, "")
    }
}
