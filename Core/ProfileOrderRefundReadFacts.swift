import Foundation

/// Mirrors the existing Profile refund payout display codes, without inferring arrival.
public enum ProfileOrderRefundReadPayout: String, CaseIterable {
    case processing, recordedComplete, manualPending, manualReview, queued, dispatching, unknown
    public init(code: Int?) {
        switch code {
        case 0: self = .processing
        case 1, 4: self = .recordedComplete
        case 2: self = .manualPending
        case 3: self = .manualReview
        case 5: self = .queued
        case 6: self = .dispatching
        default: self = .unknown
        }
    }
    public var titleKey: String { "orderRefundRead.payout." + rawValue }
}

/// Values come only from the already accepted owned-order detail, not a new wire schema.
/// Application approval, cancellation, paid amount and manual notes do not decide payout.
public struct ProfileOrderRefundReadFacts {
    public let amountText: String?
    public let applicationCode: Int?
    public let payoutCode: Int?
    public let payout: ProfileOrderRefundReadPayout
    public let manualCase: String?
    public let deadline: String?
    public init(amount: Decimal?, applicationCode: Int?, payoutCode: Int?, manualCase: String?, deadline: String?) {
        if let amount, !amount.isNaN, amount >= 0 { amountText = NSDecimalNumber(decimal: amount).stringValue }
        else { amountText = nil }
        self.applicationCode = applicationCode; self.payoutCode = payoutCode
        payout = .init(code: payoutCode)
        self.manualCase = Self.nonblank(manualCase); self.deadline = Self.nonblank(deadline)
    }
    public var hasReturnedFacts: Bool {
        amountText != nil || applicationCode != nil || payoutCode != nil || manualCase != nil || deadline != nil
    }
    /// Defense in depth only. The existing reader and owner-bound read container still
    /// authorize/fetch the detail, including reader/epoch/viewer/approval replacement.
    public static func matchesAccount(requestedID: Int, recordID: Int, memberID: Int?,
                                      identity: ProfileReadIdentity?, configured: Bool) -> Bool {
        configured && requestedID > 0 && recordID == requestedID
            && (identity?.accountID ?? 0) > 0 && memberID == identity?.accountID
    }
    private static func nonblank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
