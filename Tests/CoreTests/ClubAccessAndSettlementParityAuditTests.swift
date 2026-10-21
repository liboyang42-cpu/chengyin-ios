import XCTest
@testable import QuestifyCore

final class ClubAccessAndSettlementParityAuditTests: XCTestCase {
    func testPassingAuditVerifiesAccessMeFormPOSTGovernancePermissionsEnrollmentFormattingAndSettlement() {
        let report = ClubAccessAndSettlementParityAuditor.audit(
            accessMeContract: ClubAccessMeContractAuditInput(
                path: "/api/club/access/me",
                httpMethod: "POST",
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                acceptHeader: "application/json",
                hasValidAuthToken: true
            ),
            governanceOperations: [
                ClubGovernanceOperationAuditInput(
                    operationName: "approveMemberJoin",
                    requiredPermission: "CLUB_MANAGE_MEMBERS",
                    grantedPermissions: ["CLUB_MANAGE_MEMBERS", "CLUB_MANAGE_ACTIVITIES"],
                    didAllowDispatch: true
                ),
                ClubGovernanceOperationAuditInput(
                    operationName: "updateRoleMatrix",
                    requiredPermission: "CLUB_MANAGE_ROLES",
                    grantedPermissions: ["CLUB_MANAGE_MEMBERS"],
                    didAllowDispatch: false
                ),
            ],
            enrollmentFormatting: ClubEnrollmentFormattingAuditInput(
                activityTitle: "Night City Orienteering",
                enrolledCount: 18,
                capacity: 24,
                paidAmountFen: 9_900,
                refundedAmountFen: 3_300,
                statusLabel: "PARTIAL_REFUNDED",
                failureStatusCode: 403
            ),
            joinNotify: ClubOpsJoinNotifyAuditInput(
                clubID: 12,
                pendingApplicantCount: 4,
                notifyEnabled: true,
                latestNotifyRevision: 7
            ),
            settlement: ClubOpsSettlementAuditInput(
                clubID: 12,
                grossAmountFen: 50_000,
                platformFeeFen: 5_000,
                settledNetAmountFen: 45_000,
                settlementStatus: "SETTLED",
                readbackVerified: true
            )
        )

        XCTAssertTrue(report.isPassing)
        XCTAssertTrue(report.violations.isEmpty)
        XCTAssertEqual(report.formattedHeaderLine, "Night City Orienteering • Enrolled 18/24")
        XCTAssertEqual(report.formattedPaymentRefundSummary, "Paid ¥99.00 • Refunded ¥33.00 • PARTIAL_REFUNDED")
        XCTAssertEqual(report.formattedFailureTitle, "Club Enrollment Permission Denied")
    }

    func testAccessMeContractRejectsGETOrNonFormURLEncodedOrMissingAuthToken() {
        let wrongMethod = ClubAccessMeContractAuditInput(
            path: "/api/club/access/me",
            httpMethod: "GET",
            contentType: "application/json",
            acceptHeader: "application/json",
            hasValidAuthToken: false
        )
        let report = ClubAccessAndSettlementParityAuditor.audit(
            accessMeContract: wrongMethod,
            governanceOperations: [],
            enrollmentFormatting: ClubEnrollmentFormattingAuditInput(
                activityTitle: "Run",
                enrolledCount: 1,
                capacity: 10,
                paidAmountFen: 100,
                refundedAmountFen: 0,
                statusLabel: "PAID",
                failureStatusCode: nil
            ),
            joinNotify: ClubOpsJoinNotifyAuditInput(
                clubID: 1,
                pendingApplicantCount: 0,
                notifyEnabled: false,
                latestNotifyRevision: 1
            ),
            settlement: ClubOpsSettlementAuditInput(
                clubID: 1,
                grossAmountFen: 0,
                platformFeeFen: 0,
                settledNetAmountFen: 0,
                settlementStatus: "PENDING",
                readbackVerified: false
            )
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertTrue(report.violations.contains(.accessMeMethodOrContentTypeMismatch))
        XCTAssertTrue(report.violations.contains(.accessMeMissingAuthToken))
    }

    func testGovernanceCoordinatorBlocksOperationsMissingRequiredPermission() {
        let unauthorizedDispatch = ClubGovernanceOperationAuditInput(
            operationName: "removeClubMember",
            requiredPermission: "CLUB_MANAGE_MEMBERS",
            grantedPermissions: ["CLUB_VIEW_ONLY"],
            didAllowDispatch: true
        )
        let report = ClubAccessAndSettlementParityAuditor.audit(
            accessMeContract: ClubAccessMeContractAuditInput(),
            governanceOperations: [unauthorizedDispatch],
            enrollmentFormatting: ClubEnrollmentFormattingAuditInput(
                activityTitle: "Run",
                enrolledCount: 2,
                capacity: nil,
                paidAmountFen: 0,
                refundedAmountFen: 0,
                statusLabel: "FREE",
                failureStatusCode: 404
            ),
            joinNotify: ClubOpsJoinNotifyAuditInput(
                clubID: 1,
                pendingApplicantCount: 0,
                notifyEnabled: true,
                latestNotifyRevision: 1
            ),
            settlement: ClubOpsSettlementAuditInput(
                clubID: 1,
                grossAmountFen: 1_000,
                platformFeeFen: 100,
                settledNetAmountFen: 900,
                settlementStatus: "PENDING",
                readbackVerified: false
            )
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertEqual(
            report.violations,
            [
                .governanceOperationDispatchedWithoutPermission(
                    operation: "removeClubMember",
                    requiredPermission: "CLUB_MANAGE_MEMBERS"
                )
            ]
        )
    }

    func testEnrollmentReaderNonisolatedStaticFormattingAndValidation() {
        XCTAssertEqual(
            ClubEnrollmentFormatter.formatHeaderLine(activityTitle: "   ", enrolledCount: 5, capacity: nil),
            "Untitled Activity • Enrolled 5"
        )
        XCTAssertEqual(ClubEnrollmentFormatter.failureTitle(forStatusCode: 401), "Authentication Required")
        XCTAssertEqual(ClubEnrollmentFormatter.failureTitle(forStatusCode: 403), "Club Enrollment Permission Denied")
        XCTAssertEqual(ClubEnrollmentFormatter.failureTitle(forStatusCode: 404), "Club Activity Not Found")
        XCTAssertEqual(ClubEnrollmentFormatter.failureTitle(forStatusCode: 503), "Club Enrollment Read Unavailable")

        let mismatchedFormatting = ClubEnrollmentFormattingAuditInput(
            activityTitle: "Sprint",
            enrolledCount: 4,
            capacity: 10,
            paidAmountFen: 1_000,
            refundedAmountFen: 2_000,
            statusLabel: "INVALID_REFUND",
            failureStatusCode: 403,
            renderedHeaderLine: "Wrong Header"
        )
        let report = ClubAccessAndSettlementParityAuditor.audit(
            accessMeContract: ClubAccessMeContractAuditInput(),
            governanceOperations: [],
            enrollmentFormatting: mismatchedFormatting,
            joinNotify: ClubOpsJoinNotifyAuditInput(
                clubID: 1,
                pendingApplicantCount: 0,
                notifyEnabled: false,
                latestNotifyRevision: 1
            ),
            settlement: ClubOpsSettlementAuditInput(
                clubID: 1,
                grossAmountFen: 0,
                platformFeeFen: 0,
                settledNetAmountFen: 0,
                settlementStatus: "PENDING",
                readbackVerified: false
            )
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertTrue(report.violations.contains(.invalidEnrollmentFormattingInput))
        XCTAssertTrue(report.violations.contains(.enrollmentFormattingMismatch))
    }

    func testClubOpsJoinNotifyAndSettlementReadbackRejectNetMismatchAndUnverifiedSettled() {
        let netMismatchReport = ClubAccessAndSettlementParityAuditor.audit(
            accessMeContract: ClubAccessMeContractAuditInput(),
            governanceOperations: [],
            enrollmentFormatting: ClubEnrollmentFormattingAuditInput(
                activityTitle: "Relay",
                enrolledCount: 8,
                capacity: 16,
                paidAmountFen: 8_000,
                refundedAmountFen: 0,
                statusLabel: "PAID",
                failureStatusCode: nil
            ),
            joinNotify: ClubOpsJoinNotifyAuditInput(
                clubID: 0,
                pendingApplicantCount: -1,
                notifyEnabled: true,
                latestNotifyRevision: -1
            ),
            settlement: ClubOpsSettlementAuditInput(
                clubID: 9,
                grossAmountFen: 10_000,
                platformFeeFen: 1_000,
                settledNetAmountFen: 9_500,
                settlementStatus: "SETTLED",
                readbackVerified: true
            )
        )

        XCTAssertFalse(netMismatchReport.isPassing)
        XCTAssertTrue(netMismatchReport.violations.contains(.invalidJoinNotifyPresentation))
        XCTAssertTrue(
            netMismatchReport.violations.contains(
                .settlementNetAmountMismatch(expectedNetFen: 9_000, actualNetFen: 9_500)
            )
        )

        let unverifiedSettledReport = ClubAccessAndSettlementParityAuditor.audit(
            accessMeContract: ClubAccessMeContractAuditInput(),
            governanceOperations: [],
            enrollmentFormatting: ClubEnrollmentFormattingAuditInput(
                activityTitle: "Relay",
                enrolledCount: 8,
                capacity: 16,
                paidAmountFen: 8_000,
                refundedAmountFen: 0,
                statusLabel: "PAID",
                failureStatusCode: nil
            ),
            joinNotify: ClubOpsJoinNotifyAuditInput(
                clubID: 9,
                pendingApplicantCount: 2,
                notifyEnabled: true,
                latestNotifyRevision: 3
            ),
            settlement: ClubOpsSettlementAuditInput(
                clubID: 9,
                grossAmountFen: 10_000,
                platformFeeFen: 1_000,
                settledNetAmountFen: 9_000,
                settlementStatus: "SETTLED",
                readbackVerified: false
            )
        )
        XCTAssertFalse(unverifiedSettledReport.isPassing)
        XCTAssertEqual(unverifiedSettledReport.violations, [.unverifiedSettledStatusPresentation])
    }
}
