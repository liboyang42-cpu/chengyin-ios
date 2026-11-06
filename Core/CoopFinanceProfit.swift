import Foundation

/// Source `components/cy/scene-merchant-profit` (deep link `pages/coop/finance`), read from `api/coop/finance`.
/// Unknown facts stay unknown: a missing amount never renders as zero and never enables withdrawal support.
public struct CoopFinanceProfit: Equatable {
    public enum TopicStatus: String, Equatable {
        case settlementUnknown, unsettled, amountUnknown, noIncomeDue, arrivalUnknown, credited, awaitingCredit
        public var badge: Badge {
            switch self {
            case .credited: return .success
            case .settlementUnknown, .amountUnknown, .arrivalUnknown: return .neutral
            case .unsettled, .noIncomeDue, .awaitingCredit: return .warning
            }
        }
    }
    public enum MerchantStatus: String, Equatable { case amountUnknown, noMerchantShare, payoutUnknown, paid, partiallyPaid, unpaid }
    public enum Badge: String, Equatable { case success, neutral, warning }
    public enum WithdrawState: String, Equatable { case unknown, zero, positive }
    public enum StatKey: String, Equatable { case income, adjustPending, adjustExecuted }
    public struct Stat: Equatable {
        public let key: StatKey
        /// Two-place amount; nil renders as an em dash, never as zero.
        public let amount: Decimal?
    }
    public struct Topic: Equatable {
        public let topicID: Int?
        public let topicName: String?
        public let status: TopicStatus
        public let merchantStatus: MerchantStatus
        public let income: Decimal?
        public let totalSales: Decimal?
        public let verifiedSales: Decimal?
        public let platformAmount: Decimal?
        public let merchantTotal: Decimal?
        /// `merchantPayoutTime`, else `merchantPayableTime`, verbatim.
        public let arrivalText: String?
        /// Date prefix (10 characters) of `merchantPayoutTime` only, as the source meta line shows it.
        public let payoutDate: String?
        let weight: Int
        public var isPending: Bool { weight < 3 }
        public var canOpenDetail: Bool { (topicID ?? 0) > 0 }
    }

    public let topics: [Topic]
    public let myIncomeTotal: Decimal?
    public let withdrawState: WithdrawState
    public let pendingCount: Int
    public let stats: [Stat]
    public let adjustReason: String?
    /// Balance segments are owner-only; the server decides and the client never guesses.
    public let isOwner: Bool
    public var canWithdraw: Bool { withdrawState == .positive }

    /// Accepts the `data` object of a successful envelope. Any non-object topic row rejects the whole read.
    public init(_ data: CoopFlowJSON) throws {
        guard case .object = data, let rows = data["topics"].rows else { throw CoopFlowFailure.malformed }
        var total = Decimal(0)
        var unknownIncome = false
        var mapped: [Topic] = []
        for row in rows {
            guard case .object = row else { throw CoopFlowFailure.malformed }
            let settled = row["settled"].flag
            let arrived = row["myIncomeArrived"].flag
            let income = Self.amount(row["myIncome"])
            let cleared = settled == true && income != nil && (income == 0 || arrived == true)
            if cleared, let income { total += income }
            if settled == nil || (settled == true && (income == nil || (income! > 0 && arrived == nil))) { unknownIncome = true }
            let merchantTotal = Self.amount(row["merchantTotal"])
            let merchantPaid = Self.amount(row["merchantPaid"])
            let merchant: MerchantStatus
            if let merchantTotal {
                if merchantTotal <= 0 { merchant = .noMerchantShare }
                else if let merchantPaid { merchant = merchantPaid >= merchantTotal ? .paid : merchantPaid > 0 ? .partiallyPaid : .unpaid }
                else { merchant = .payoutUnknown }
            } else { merchant = .amountUnknown }
            let status: TopicStatus
            switch settled {
            case nil: status = .settlementUnknown
            case false?: status = .unsettled
            case true?:
                if let income {
                    if income == 0 { status = .noIncomeDue }
                    else if let arrived { status = arrived ? .credited : .awaitingCredit }
                    else { status = .arrivalUnknown }
                } else { status = .amountUnknown }
            }
            let weight: Int
            if settled != true { weight = 0 }
            else if income == nil || arrived == nil { weight = 1 }
            else if !cleared || [.amountUnknown, .payoutUnknown, .unpaid, .partiallyPaid].contains(merchant) { weight = 2 }
            else { weight = 3 }
            let payout = Self.nonEmpty(row["merchantPayoutTime"].text)
            mapped.append(Topic(topicID: row["topicId"].integer, topicName: Self.nonEmpty(row["topicName"].text),
                status: status, merchantStatus: merchant, income: income,
                totalSales: Self.amount(row["totalSales"]), verifiedSales: Self.amount(row["verifiedSales"]),
                platformAmount: Self.amount(row["platformAmount"]), merchantTotal: merchantTotal,
                arrivalText: payout ?? Self.nonEmpty(row["merchantPayableTime"].text),
                payoutDate: payout.map { String($0.prefix(10)) }, weight: weight))
        }
        // Stable: rows still needing follow-up precede settled ones, otherwise server order is kept.
        topics = mapped.enumerated().sorted { ($0.element.weight, $0.offset) < ($1.element.weight, $1.offset) }.map(\.element)
        myIncomeTotal = unknownIncome ? nil : Self.round(total)
        withdrawState = myIncomeTotal.map { $0 > 0 ? .positive : .zero } ?? .unknown
        pendingCount = topics.filter(\.isPending).count
        let adjustments = data["adjustments"]
        let pending = Self.adjustment(adjustments["pendingAmount"])
        let executed = Self.adjustment(adjustments["executedAmount"])
        var stats = [Stat(key: .income, amount: myIncomeTotal)]
        if pending == nil || pending! > 0 { stats.append(Stat(key: .adjustPending, amount: pending)) }
        if executed == nil || executed! > 0 { stats.append(Stat(key: .adjustExecuted, amount: executed)) }
        self.stats = stats
        adjustReason = adjustments["pendingReason"].text.flatMap { Self.nonEmpty($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        isOwner = data["isOwner"].flag == true
    }

    /// Topic money: JSON numbers only, finite and non-negative, rounded to cents.
    static func amount(_ value: CoopFlowJSON) -> Decimal? {
        guard case .number(let number) = value, !number.isNaN, number >= 0 else { return nil }
        return round(number)
    }
    /// Adjustment money: numbers or numeric strings (the source coerces with Number()); blank is unknown.
    static func adjustment(_ value: CoopFlowJSON) -> Decimal? {
        switch value {
        case .number(let number): return number.isNaN ? nil : round(number)
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let number = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
                  trimmed.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil else { return nil }
            return round(number)
        default: return nil
        }
    }
    static func round(_ value: Decimal) -> Decimal {
        var input = value, output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }
    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}

public extension CoopFinanceProfit {
    /// Read outcome classes the page distinguishes (source `authRequired` / `accessDenied` / `loadErr`).
    enum ReadIssue: Equatable { case authRequired, accessDenied, failed }
    static func issue(for error: Error) -> ReadIssue {
        if error as? APIError == .unauthorized { return .authRequired }
        switch error as? CoopFlowFailure {
        case .server(401, _)?: return .authRequired
        case .server(403, _)?, .permission?: return .accessDenied
        default: return .failed
        }
    }
    /// Two-place, invariant amount text without currency symbol (source `toFixed(2)`).
    static func plainText(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? NSDecimalNumber(decimal: amount).stringValue
    }
}
