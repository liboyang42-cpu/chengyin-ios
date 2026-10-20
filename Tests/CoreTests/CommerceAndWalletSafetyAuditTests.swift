import XCTest
@testable import QuestifyCore

final class CommerceAndWalletSafetyAuditTests: XCTestCase {
    func testAllFivePillarsPassWhenWalletWithdrawalPointsRefundRedemptionAndRewardLedgerObeyInvariants() {
        let report = CommerceAndWalletSafetyAuditor.audit(
            walletRead: WalletReadSafetyInput(
                status: .ok,
                displayedBalanceFen: 12_800,
                incomeSourceCodes: ["CREATOR", "BRAND", "创", "品"]
            ),
            withdrawalGate: WithdrawalGateSafetyInput(
                isWithdrawalEndpointApproved: false,
                hasActiveAuthenticatedSession: true,
                historyReadSucceeded: false,
                requestedAmountFen: 5_000,
                availableBalanceFen: nil,
                didAllowApplySubmission: false
            ),
            pointsCancelReadbacks: [
                AssetPointsCancelReadbackInput(
                    orderID: "ord-1001",
                    deductedPoints: 300,
                    balanceBeforeCancel: 1_200,
                    balanceAfterReadback: 1_500,
                    ledgerReturnEntryPoints: 300,
                    cancelReceiptConfirmed: true,
                    markedAsReturnedInUI: true
                ),
            ],
            orderLines: [
                OrderLineFulfilmentAndRefundInput(
                    lineID: "line-1",
                    entitlementState: "GRANTED",
                    fulfilmentState: "REDEEMED",
                    refundStatus: .idle,
                    redemptionStep: .finalRedeemed,
                    hadVerifiedPreviewBeforeFinal: true,
                    previewTokenMatchesFinal: true
                ),
                OrderLineFulfilmentAndRefundInput(
                    lineID: "line-2",
                    entitlementState: "REFUNDING",
                    fulfilmentState: "UNFULFILLED",
                    refundStatus: .unknownLocked,
                    lockedRefundRequestID: "refund-req-77",
                    attemptedRefundRequestID: "refund-req-77",
                    redemptionStep: .none
                ),
            ],
            rewardLedger: [
                RewardLedgerAuditEntry(entryID: "rw-1", sequence: 1, deltaPoints: 50),
                RewardLedgerAuditEntry(entryID: "rw-2", sequence: 2, deltaPoints: 120),
            ]
        )

        XCTAssertTrue(report.isPassing)
        XCTAssertTrue(report.violations.isEmpty)
        XCTAssertEqual(report.verifiedPillars, CommerceAndWalletSafetyPillar.allCases)
        XCTAssertEqual(
            report.resolvedIncomeBadges,
            [.creator, .brand, .creator, .brand]
        )
    }

    func testW203ForbiddenOrUnavailableWalletReadAndW205WithdrawalGateFailClosed() {
        let forbiddenRead = WalletReadSafetyInput(
            status: .forbidden403,
            displayedBalanceFen: 0,
            incomeSourceCodes: ["UNKNOWN_SOURCE"]
        )
        let bypassedWithdrawal = WithdrawalGateSafetyInput(
            isWithdrawalEndpointApproved: false,
            hasActiveAuthenticatedSession: true,
            historyReadSucceeded: false,
            requestedAmountFen: 1_000,
            availableBalanceFen: nil,
            didAllowApplySubmission: true
        )

        let report = CommerceAndWalletSafetyAuditor.audit(
            walletRead: forbiddenRead,
            withdrawalGate: bypassedWithdrawal,
            pointsCancelReadbacks: [],
            orderLines: [],
            rewardLedger: []
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertTrue(report.violations.contains(.fabricatedBalanceOnUnavailableOrForbiddenRead))
        XCTAssertTrue(report.violations.contains(.invalidIncomeSourceBadge("UNKNOWN_SOURCE")))
        XCTAssertTrue(report.violations.contains(.withdrawalGateNotFailClosed))
    }

    func testI04OrderCancelPointsReturnRequiresAuthoritativeLedgerReadback() {
        let unverifiedCancel = AssetPointsCancelReadbackInput(
            orderID: "ord-2002",
            deductedPoints: 200,
            balanceBeforeCancel: 800,
            balanceAfterReadback: 800,
            ledgerReturnEntryPoints: nil,
            cancelReceiptConfirmed: false,
            markedAsReturnedInUI: true
        )

        let report = CommerceAndWalletSafetyAuditor.audit(
            walletRead: WalletReadSafetyInput(status: .unavailable, displayedBalanceFen: nil),
            withdrawalGate: WithdrawalGateSafetyInput(
                isWithdrawalEndpointApproved: false,
                hasActiveAuthenticatedSession: false,
                historyReadSucceeded: false,
                requestedAmountFen: 0,
                availableBalanceFen: nil,
                didAllowApplySubmission: false
            ),
            pointsCancelReadbacks: [unverifiedCancel],
            orderLines: [],
            rewardLedger: []
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertEqual(
            report.violations,
            [.unverifiedOrderCancelPointsReturn(orderID: "ord-2002")]
        )
    }

    func testGW06W07UnknownRefundRetryLockAndTwoStepStaffRedemptionEnforcement() {
        let rekeyedUnknownRefundLine = OrderLineFulfilmentAndRefundInput(
            lineID: "line-unknown-rekey",
            entitlementState: "REFUNDING",
            fulfilmentState: "UNFULFILLED",
            refundStatus: .unknownLocked,
            lockedRefundRequestID: "refund-req-original",
            attemptedRefundRequestID: "refund-req-new-id",
            redemptionStep: .none
        )
        let bypassedPreviewRedemptionLine = OrderLineFulfilmentAndRefundInput(
            lineID: "line-bypass-preview",
            entitlementState: "GRANTED",
            fulfilmentState: "REDEEMED",
            refundStatus: .idle,
            redemptionStep: .finalRedeemed,
            hadVerifiedPreviewBeforeFinal: false,
            previewTokenMatchesFinal: false
        )
        let conflatedStateLine = OrderLineFulfilmentAndRefundInput(
            lineID: "line-conflated",
            entitlementState: "REDEEMED",
            fulfilmentState: "REDEEMED"
        )

        let report = CommerceAndWalletSafetyAuditor.audit(
            walletRead: WalletReadSafetyInput(status: .unavailable, displayedBalanceFen: nil),
            withdrawalGate: WithdrawalGateSafetyInput(
                isWithdrawalEndpointApproved: false,
                hasActiveAuthenticatedSession: false,
                historyReadSucceeded: false,
                requestedAmountFen: 0,
                availableBalanceFen: nil,
                didAllowApplySubmission: false
            ),
            pointsCancelReadbacks: [],
            orderLines: [rekeyedUnknownRefundLine, bypassedPreviewRedemptionLine, conflatedStateLine],
            rewardLedger: []
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertTrue(report.violations.contains(.unknownRefundLockViolation(lineID: "line-unknown-rekey")))
        XCTAssertTrue(report.violations.contains(.twoStepStaffRedemptionBypassed(lineID: "line-bypass-preview")))
        XCTAssertTrue(report.violations.contains(.entitlementAndFulfilmentConflated(lineID: "line-conflated")))
    }

    func testGW075W174RewardLedgerDetectsCashRedemptionTransferAndAppendOnlyViolations() {
        let report = CommerceAndWalletSafetyAuditor.audit(
            walletRead: WalletReadSafetyInput(status: .unavailable, displayedBalanceFen: nil),
            withdrawalGate: WithdrawalGateSafetyInput(
                isWithdrawalEndpointApproved: false,
                hasActiveAuthenticatedSession: false,
                historyReadSucceeded: false,
                requestedAmountFen: 0,
                availableBalanceFen: nil,
                didAllowApplySubmission: false
            ),
            pointsCancelReadbacks: [],
            orderLines: [],
            rewardLedger: [
                RewardLedgerAuditEntry(entryID: "rw-10", sequence: 10, deltaPoints: 100),
                RewardLedgerAuditEntry(
                    entryID: "rw-cash-illegal",
                    sequence: 9,
                    deltaPoints: -50,
                    allowsCashRedemption: true,
                    allowsWithdrawal: true,
                    allowsMemberTransfer: false,
                    overwritesPriorEntry: true
                ),
            ]
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertTrue(report.violations.contains(.appendOnlyRewardLedgerViolation(entryID: "rw-cash-illegal")))
        XCTAssertTrue(report.violations.contains(.cashRedemptionOrTransferViolation(entryID: "rw-cash-illegal")))
    }
}
