import Foundation

/// Pure value-type safety auditor covering the 5 commerce & wallet safety pillars:
/// 1. `w2-03` wallet read failure & 403/unavailable safe presentation + income source badge (`创` / `品`),
/// 2. `w2-05` withdrawal apply & history fail-closed gate,
/// 3. `I04` asset points ledger readback & order cancellation points return verification,
/// 4. `G-W06/W07` per-line fulfilment vs entitlement separation, `UNKNOWN` refund retry lock,
///    and two-step staff redemption (`preview` -> `final`),
/// 5. `G-W07.5 / W17.4` append-only reward ledger with non-cash, non-withdrawable, non-transferable enforcement.
public enum CommerceAndWalletSafetyPillar: String, CaseIterable, Equatable, Sendable {
    case walletReadAndIncomeBadgeW203 = "W2_03_WALLET_READ_AND_BADGE"
    case withdrawalFailClosedGateW205 = "W2_05_WITHDRAWAL_FAIL_CLOSED_GATE"
    case assetPointsCancelReadbackI04 = "I04_ASSET_POINTS_CANCEL_READBACK"
    case lineFulfilmentRefundAndTwoStepRedemptionGW06W07 = "G_W06_W07_LINE_REFUND_AND_REDEMPTION"
    case appendOnlyNonCashRewardLedgerGW075W174 = "G_W07_5_W17_4_REWARD_LEDGER"
}

public enum CommerceAndWalletSafetyViolation: Equatable, Sendable {
    case fabricatedBalanceOnUnavailableOrForbiddenRead
    case invalidIncomeSourceBadge(String)
    case withdrawalGateNotFailClosed
    case unverifiedOrderCancelPointsReturn(orderID: String)
    case entitlementAndFulfilmentConflated(lineID: String)
    case unknownRefundLockViolation(lineID: String)
    case twoStepStaffRedemptionBypassed(lineID: String)
    case appendOnlyRewardLedgerViolation(entryID: String)
    case cashRedemptionOrTransferViolation(entryID: String)
}

/// Pillar 1 (`w2-03`): Income source badge (`创` for creator/workshop, `品` for brand/merchant).
public enum WalletIncomeSourceBadge: String, CaseIterable, Equatable, Sendable {
    case creator = "创"
    case brand = "品"

    public static func resolve(sourceCode: String) -> WalletIncomeSourceBadge? {
        switch sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "CREATOR", "WORKSHOP", "TEMPLATE", "创":
            return .creator
        case "BRAND", "MERCHANT", "STORE", "品":
            return .brand
        default:
            return nil
        }
    }
}

public struct WalletReadSafetyInput: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case ok = "OK"
        case forbidden403 = "FORBIDDEN_403"
        case unavailable = "UNAVAILABLE"
    }

    public let status: Status
    public let displayedBalanceFen: Int64?
    public let incomeSourceCodes: [String]

    public init(
        status: Status,
        displayedBalanceFen: Int64?,
        incomeSourceCodes: [String] = []
    ) {
        self.status = status
        self.displayedBalanceFen = displayedBalanceFen
        self.incomeSourceCodes = incomeSourceCodes
    }
}

/// Pillar 2 (`w2-05`): Withdrawal apply & history fail-closed gate input.
public struct WithdrawalGateSafetyInput: Equatable, Sendable {
    public let isWithdrawalEndpointApproved: Bool
    public let hasActiveAuthenticatedSession: Bool
    public let historyReadSucceeded: Bool
    public let requestedAmountFen: Int64
    public let availableBalanceFen: Int64?
    public let didAllowApplySubmission: Bool

    public init(
        isWithdrawalEndpointApproved: Bool,
        hasActiveAuthenticatedSession: Bool,
        historyReadSucceeded: Bool,
        requestedAmountFen: Int64,
        availableBalanceFen: Int64?,
        didAllowApplySubmission: Bool
    ) {
        self.isWithdrawalEndpointApproved = isWithdrawalEndpointApproved
        self.hasActiveAuthenticatedSession = hasActiveAuthenticatedSession
        self.historyReadSucceeded = historyReadSucceeded
        self.requestedAmountFen = requestedAmountFen
        self.availableBalanceFen = availableBalanceFen
        self.didAllowApplySubmission = didAllowApplySubmission
    }

    public var shouldAllowApply: Bool {
        guard isWithdrawalEndpointApproved,
              hasActiveAuthenticatedSession,
              historyReadSucceeded,
              let availableBalanceFen,
              requestedAmountFen > 0,
              requestedAmountFen <= availableBalanceFen
        else {
            return false
        }
        return true
    }
}

/// Pillar 3 (`I04`): Asset points ledger readback & order cancellation points return verification.
public struct AssetPointsCancelReadbackInput: Equatable, Sendable {
    public let orderID: String
    public let deductedPoints: Int64
    public let balanceBeforeCancel: Int64
    public let balanceAfterReadback: Int64?
    public let ledgerReturnEntryPoints: Int64?
    public let cancelReceiptConfirmed: Bool
    public let markedAsReturnedInUI: Bool

    public init(
        orderID: String,
        deductedPoints: Int64,
        balanceBeforeCancel: Int64,
        balanceAfterReadback: Int64?,
        ledgerReturnEntryPoints: Int64?,
        cancelReceiptConfirmed: Bool,
        markedAsReturnedInUI: Bool
    ) {
        self.orderID = orderID
        self.deductedPoints = deductedPoints
        self.balanceBeforeCancel = balanceBeforeCancel
        self.balanceAfterReadback = balanceAfterReadback
        self.ledgerReturnEntryPoints = ledgerReturnEntryPoints
        self.cancelReceiptConfirmed = cancelReceiptConfirmed
        self.markedAsReturnedInUI = markedAsReturnedInUI
    }

    public var isReturnAuthoritativelyVerified: Bool {
        guard cancelReceiptConfirmed,
              deductedPoints >= 0,
              balanceBeforeCancel >= 0,
              let balanceAfterReadback,
              let ledgerReturnEntryPoints
        else {
            return false
        }
        return ledgerReturnEntryPoints == deductedPoints
            && balanceAfterReadback == balanceBeforeCancel + deductedPoints
    }
}

/// Pillar 4 (`G-W06/W07`): Per-line fulfilment vs entitlement separation, `UNKNOWN` refund retry lock,
/// and two-step staff redemption (`preview` -> `final`).
public enum RefundAttemptAuditStatus: String, Equatable, Sendable {
    case idle = "IDLE"
    case unknownLocked = "UNKNOWN"
    case applied = "APPLIED"
    case rejected = "REJECTED"
}

public enum StaffRedemptionStep: String, Equatable, Sendable {
    case none = "NONE"
    case previewVerified = "PREVIEW_VERIFIED"
    case finalRedeemed = "FINAL_REDEEMED"
}

public struct OrderLineFulfilmentAndRefundInput: Equatable, Sendable {
    public let lineID: String
    public let entitlementState: String
    public let fulfilmentState: String
    public let refundStatus: RefundAttemptAuditStatus
    public let lockedRefundRequestID: String?
    public let attemptedRefundRequestID: String?
    public let redemptionStep: StaffRedemptionStep
    public let hadVerifiedPreviewBeforeFinal: Bool
    public let previewTokenMatchesFinal: Bool

    public init(
        lineID: String,
        entitlementState: String,
        fulfilmentState: String,
        refundStatus: RefundAttemptAuditStatus = .idle,
        lockedRefundRequestID: String? = nil,
        attemptedRefundRequestID: String? = nil,
        redemptionStep: StaffRedemptionStep = .none,
        hadVerifiedPreviewBeforeFinal: Bool = false,
        previewTokenMatchesFinal: Bool = false
    ) {
        self.lineID = lineID
        self.entitlementState = entitlementState
        self.fulfilmentState = fulfilmentState
        self.refundStatus = refundStatus
        self.lockedRefundRequestID = lockedRefundRequestID
        self.attemptedRefundRequestID = attemptedRefundRequestID
        self.redemptionStep = redemptionStep
        self.hadVerifiedPreviewBeforeFinal = hadVerifiedPreviewBeforeFinal
        self.previewTokenMatchesFinal = previewTokenMatchesFinal
    }
}

/// Pillar 5 (`G-W07.5 / W17.4`): Append-only reward ledger entry with non-cash,
/// non-withdrawable, non-transferable enforcement.
public struct RewardLedgerAuditEntry: Equatable, Sendable {
    public let entryID: String
    public let sequence: Int64
    public let deltaPoints: Int64
    public let allowsCashRedemption: Bool
    public let allowsWithdrawal: Bool
    public let allowsMemberTransfer: Bool
    public let overwritesPriorEntry: Bool

    public init(
        entryID: String,
        sequence: Int64,
        deltaPoints: Int64,
        allowsCashRedemption: Bool = false,
        allowsWithdrawal: Bool = false,
        allowsMemberTransfer: Bool = false,
        overwritesPriorEntry: Bool = false
    ) {
        self.entryID = entryID
        self.sequence = sequence
        self.deltaPoints = deltaPoints
        self.allowsCashRedemption = allowsCashRedemption
        self.allowsWithdrawal = allowsWithdrawal
        self.allowsMemberTransfer = allowsMemberTransfer
        self.overwritesPriorEntry = overwritesPriorEntry
    }
}

public struct CommerceAndWalletSafetyAuditReport: Equatable, Sendable {
    public let verifiedPillars: [CommerceAndWalletSafetyPillar]
    public let resolvedIncomeBadges: [WalletIncomeSourceBadge]
    public let violations: [CommerceAndWalletSafetyViolation]

    public var isPassing: Bool {
        violations.isEmpty && verifiedPillars.count == CommerceAndWalletSafetyPillar.allCases.count
    }
}

public enum CommerceAndWalletSafetyAuditor {
    public static func audit(
        walletRead: WalletReadSafetyInput,
        withdrawalGate: WithdrawalGateSafetyInput,
        pointsCancelReadbacks: [AssetPointsCancelReadbackInput],
        orderLines: [OrderLineFulfilmentAndRefundInput],
        rewardLedger: [RewardLedgerAuditEntry]
    ) -> CommerceAndWalletSafetyAuditReport {
        var violations: [CommerceAndWalletSafetyViolation] = []
        var verifiedPillars: [CommerceAndWalletSafetyPillar] = []
        var badges: [WalletIncomeSourceBadge] = []

        // Pillar 1: w2-03 wallet read failure & 403/unavailable safe presentation + income source badge (创 / 品)
        let walletViolationCountBefore = violations.count
        switch walletRead.status {
        case .ok:
            if let balance = walletRead.displayedBalanceFen, balance < 0 {
                violations.append(.fabricatedBalanceOnUnavailableOrForbiddenRead)
            } else if walletRead.displayedBalanceFen == nil {
                violations.append(.fabricatedBalanceOnUnavailableOrForbiddenRead)
            }
        case .forbidden403, .unavailable:
            if walletRead.displayedBalanceFen != nil {
                violations.append(.fabricatedBalanceOnUnavailableOrForbiddenRead)
            }
        }
        for code in walletRead.incomeSourceCodes {
            if let badge = WalletIncomeSourceBadge.resolve(sourceCode: code) {
                badges.append(badge)
            } else {
                violations.append(.invalidIncomeSourceBadge(code))
            }
        }
        if violations.count == walletViolationCountBefore {
            verifiedPillars.append(.walletReadAndIncomeBadgeW203)
        }

        // Pillar 2: w2-05 withdrawal apply & history fail-closed gate
        if withdrawalGate.didAllowApplySubmission && !withdrawalGate.shouldAllowApply {
            violations.append(.withdrawalGateNotFailClosed)
        } else {
            verifiedPillars.append(.withdrawalFailClosedGateW205)
        }

        // Pillar 3: I04 asset points ledger readback & order cancellation points return verification
        let i04ViolationCountBefore = violations.count
        for item in pointsCancelReadbacks {
            if item.markedAsReturnedInUI && !item.isReturnAuthoritativelyVerified {
                violations.append(.unverifiedOrderCancelPointsReturn(orderID: item.orderID))
            }
        }
        if violations.count == i04ViolationCountBefore {
            verifiedPillars.append(.assetPointsCancelReadbackI04)
        }

        // Pillar 4: G-W06/W07 per-line fulfilment vs entitlement separation, UNKNOWN refund retry lock,
        // and two-step staff redemption (preview -> final)
        let lineViolationCountBefore = violations.count
        for line in orderLines {
            let trimmedEntitlement = line.entitlementState.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedFulfilment = line.fulfilmentState.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedEntitlement.isEmpty || trimmedFulfilment.isEmpty || trimmedEntitlement == trimmedFulfilment {
                violations.append(.entitlementAndFulfilmentConflated(lineID: line.lineID))
            }

            if line.refundStatus == .unknownLocked {
                guard let lockedID = line.lockedRefundRequestID, !lockedID.isEmpty else {
                    violations.append(.unknownRefundLockViolation(lineID: line.lineID))
                    continue
                }
                if let attemptedID = line.attemptedRefundRequestID, attemptedID != lockedID {
                    violations.append(.unknownRefundLockViolation(lineID: line.lineID))
                }
                if line.redemptionStep == .finalRedeemed {
                    violations.append(.unknownRefundLockViolation(lineID: line.lineID))
                }
            }

            if line.redemptionStep == .finalRedeemed {
                if !line.hadVerifiedPreviewBeforeFinal || !line.previewTokenMatchesFinal || line.entitlementState != "GRANTED" {
                    violations.append(.twoStepStaffRedemptionBypassed(lineID: line.lineID))
                }
            }
        }
        if violations.count == lineViolationCountBefore {
            verifiedPillars.append(.lineFulfilmentRefundAndTwoStepRedemptionGW06W07)
        }

        // Pillar 5: G-W07.5 / W17.4 append-only reward ledger with non-cash, non-withdrawable, non-transferable enforcement
        let rewardViolationCountBefore = violations.count
        var previousSequence: Int64 = 0
        for entry in rewardLedger {
            if entry.overwritesPriorEntry || entry.sequence <= previousSequence || entry.entryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                violations.append(.appendOnlyRewardLedgerViolation(entryID: entry.entryID))
            }
            if entry.allowsCashRedemption || entry.allowsWithdrawal || entry.allowsMemberTransfer {
                violations.append(.cashRedemptionOrTransferViolation(entryID: entry.entryID))
            }
            if entry.sequence > previousSequence {
                previousSequence = entry.sequence
            }
        }
        if violations.count == rewardViolationCountBefore {
            verifiedPillars.append(.appendOnlyNonCashRewardLedgerGW075W174)
        }

        return CommerceAndWalletSafetyAuditReport(
            verifiedPillars: verifiedPillars,
            resolvedIncomeBadges: badges,
            violations: violations
        )
    }
}
