import Foundation

/// 主办分润 header (mini-program `scene-merchant-profit` statItems/adjustReason) built
/// from the existing `/api/coop/finance` payload. Unknown never becomes ¥0.00.
public struct CoopFinanceSummary: Equatable {
    /// Sum of 我的分润 over cleared topics; nil when any settled topic's income or arrival is unknown.
    public let creditedIncome: Decimal?
    /// nil = the server could not compute it (shown as "—"); hidden when exactly zero.
    public let pendingAdjustment: Decimal?
    public let showsPendingAdjustment: Bool
    public let executedAdjustment: Decimal?
    public let showsExecutedAdjustment: Bool
    public let pendingReason: String?
    public let isOwner: Bool

    public init(_ value: CoopFlowJSON) {
        var total = Decimal(0), unknown = false
        for topic in value["topics"].rows ?? [] {
            let settled = topic["settled"].flag
            let arrived = topic["myIncomeArrived"].flag
            let income = Self.money(topic["myIncome"])
            if settled == true, let income, income == 0 || arrived == true { total += income }
            if settled == nil || (settled == true && (income == nil || (income! > 0 && arrived == nil))) { unknown = true }
        }
        creditedIncome = unknown ? nil : total
        let adjustments = value["adjustments"]
        pendingAdjustment = Self.money(adjustments["pendingAmount"])
        showsPendingAdjustment = pendingAdjustment.map { $0 > 0 } ?? true
        executedAdjustment = Self.money(adjustments["executedAmount"])
        showsExecutedAdjustment = executedAdjustment.map { $0 > 0 } ?? true
        let reason = adjustments["pendingReason"].text?.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingReason = (reason?.isEmpty ?? true) ? nil : reason
        isOwner = value["isOwner"].flag == true
    }

    /// Source `money`: a finite, non-negative JSON number; strings and negatives are unknown.
    static func money(_ value: CoopFlowJSON) -> Decimal? {
        guard case .number(let number) = value, number >= 0 else { return nil }
        return number
    }
}
