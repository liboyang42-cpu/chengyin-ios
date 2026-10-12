import Foundation

/// Supplemental read-only facts for P120 classification. Existing ProfileOrder fields,
/// requests and all payment/refund eligibility remain unchanged.
public struct ProfileOrderHistoryFacts: Decodable, Equatable {
    public let totalAmountIsZero: Bool
    public let hasRefundApplication: Bool
    public let firstSuccessfulScanAt: String?
    public let start: String?
    public let end: String?
    private enum CodingKeys: String, CodingKey { case totalAmount, refundApplication, firstSuccessfulScanAt, cmsActivity, cmsTopic }
    private struct Owner: Decodable {
        let startDate: String?
        let startTime: String?
        let endDate: String?
        let endTime: String?
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let number = try? c.decode(Decimal.self, forKey: .totalAmount) {
            totalAmountIsZero = !number.isNaN && number == .zero
        } else if let text = try? c.decode(String.self, forKey: .totalAmount) {
            // Only an explicit complete zero literal. Decimal(string:) accepts numeric
            // prefixes, so never classify "0invalid" as a free order.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            totalAmountIsZero = trimmed.range(of: #"^[+-]?(?:0+(?:\.0*)?|\.0+)(?:[eE][+-]?[0-9]+)?$"#,
                                             options: .regularExpression) != nil
        } else { totalAmountIsZero = false }
        hasRefundApplication = c.contains(.refundApplication) && (try? c.decodeNil(forKey: .refundApplication)) == false
        firstSuccessfulScanAt = try? c.decode(String.self, forKey: .firstSuccessfulScanAt)
        let owner = (try? c.decode(Owner.self, forKey: .cmsActivity)) ?? (try? c.decode(Owner.self, forKey: .cmsTopic))
        func present(_ text: String?) -> String? { text?.isEmpty == false ? text : nil }
        start = present(owner?.startDate) ?? present(owner?.startTime)
        end = present(owner?.endDate) ?? present(owner?.endTime) ?? start
    }
}

/// Local Mini order-status.js projection only. Never use this classification to permit
/// payment, cancellation, refunds, verification, access or receipt acknowledgement.
public extension ProfileOrder {
    func historyState(now: Date = Date()) -> OrderLifecycleState {
        if manualRefundCaseStatus?.isEmpty == false { return .manualRefund }
        if historyFacts.hasRefundApplication {
            if refundPayoutStatus == 1 || refundPayoutStatus == 4 { return .refunded }
            if refundPayoutStatus == 2 || refundPayoutStatus == 3 { return .refunding }
            if (refundAmount.map { $0 > .zero } ?? true), refundApplicationStatus != 2 { return .refunding }
        }
        switch registrationStatus {
        case 1: return .pendingPayment
        case 3: return .cancelled
        case 4: return .expired
        case 2: break
        default: return .unknown
        }
        if verificationStatus == 1 { return .completed }
        if paymentStatus == 2, OrderLifecycleTime.date(historyFacts.firstSuccessfulScanAt) != nil { return .completed }
        let free = historyFacts.totalAmountIsZero && payableAmount == .zero
            && (pointPaymentAmount == nil || pointPaymentAmount == .zero)
            && (wechatPaymentAmount == nil || wechatPaymentAmount == .zero)
        if !free && refundable == false { return .nonRefundable }
        if let end = OrderLifecycleTime.date(historyFacts.end), now > end { return .completed }
        if let start = OrderLifecycleTime.date(historyFacts.start), now < start { return .notStarted }
        return .inProgress
    }
}

public enum ProfileOrderHistoryFilter: String, CaseIterable, Identifiable, Hashable {
    case all, pendingPayment, notStarted, inProgress, completed, refunding, refunded, nonRefundable, manualRefund
    public var id: String { rawValue }
    public var titleKey: String {
        self == .all ? "profile.orderFilter.all" : "orderLifecycle.state." + rawValue
    }
    public func orders(in rows: [ProfileOrder], now: Date = Date()) -> [ProfileOrder] {
        self == .all ? rows : rows.filter { $0.historyState(now: now).rawValue == rawValue }
    }
}

public struct ProfileOrderFilterOwner: Equatable {
    public let readerID: ObjectIdentifier
    public let identity: ProfileReadIdentity?
    public let isConfigured: Bool
    public init(readerID: ObjectIdentifier, identity: ProfileReadIdentity?, isConfigured: Bool) {
        self.readerID = readerID; self.identity = identity; self.isConfigured = isConfigured
    }
    public var isCurrent: Bool { isConfigured && (identity?.accountID ?? 0) > 0 }
}
/// No order/PII snapshot retained here. Detail navigation preserves the choice;
/// reader replacement, revocation or account change cannot reuse a previous choice.
public struct ProfileOrderFilterSelection {
    private var owner: ProfileOrderFilterOwner?
    private var filter: ProfileOrderHistoryFilter = .all
    public init() {}
    public func value(for current: ProfileOrderFilterOwner) -> ProfileOrderHistoryFilter {
        owner == current && current.isCurrent ? filter : .all
    }
    public mutating func choose(_ next: ProfileOrderHistoryFilter, rendered: ProfileOrderFilterOwner, current: ProfileOrderFilterOwner) {
        guard rendered == current, current.isCurrent else { return }
        owner = current; filter = next
    }
    public mutating func retire() { owner = nil; filter = .all }
}
