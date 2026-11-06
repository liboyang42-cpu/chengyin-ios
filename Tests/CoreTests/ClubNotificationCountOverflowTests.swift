import XCTest
@testable import QuestifyCore

final class ClubNotificationCountOverflowTests: XCTestCase {
    private func value(_ total: Int, _ success: Int, _ failed: Int) -> ClubGovernanceValue {
        .object(["id": .integer(7), "totalCount": .integer(total), "successCount": .integer(success),
                 "failedCount": .integer(failed), "status": .string("PROCESSING")])
    }
    func testOverflowingDeliveredSumIsRejectedNotTrappedOrAccepted() {
        for row in [value(Int.max, Int.max, 1), value(Int.max, Int.max, Int.max), value(0, Int.max, Int.max)] {
            XCTAssertThrowsError(try ClubGovernanceValidation.campaign(row)) { error in
                XCTAssertEqual(error as? ClubGovernanceFailure, .malformed)
            }
        }
    }
    func testValidExtremeAndNormalCountsRetainPendingSemantics() throws {
        for (total, success, failed, pending) in [(Int.max, Int.max - 1, 1, 0), (Int.max, 0, 0, Int.max), (10, 3, 2, 5)] {
            let row = value(total, success, failed)
            try ClubGovernanceValidation.campaign(row, expectedID: 7)
            let projected = try ClubOpsNotifyCampaign(value: row)
            XCTAssertEqual(projected.pendingCount, pending)
            XCTAssertEqual(projected.canRetryFailed, failed > 0)
            XCTAssertTrue(projected.processing)
        }
    }
    func testStandaloneDisplayClampsInconsistentCountsWithoutOverflow() throws {
        let projected = try ClubOpsNotifyCampaign(value: value(0, Int.max, Int.max))
        XCTAssertEqual(projected.pendingCount, 0)
        // Display construction is not the validating receipt path or permission to retry.
        XCTAssertThrowsError(try ClubGovernanceValidation.campaign(value(0, Int.max, Int.max)))
    }
    func testNegativeCountsWrongIdentityAndOverTotalStillReject() {
        XCTAssertThrowsError(try ClubGovernanceValidation.campaign(value(3, 2, 2)))
        XCTAssertThrowsError(try ClubGovernanceValidation.campaign(value(-1, 0, 0)))
        XCTAssertThrowsError(try ClubGovernanceValidation.campaign(value(3, -1, 0)))
        XCTAssertThrowsError(try ClubGovernanceValidation.campaign(value(3, 0, -1)))
        XCTAssertThrowsError(try ClubGovernanceValidation.campaign(value(3, 1, 1), expectedID: 8))
    }
}
