import Foundation

/// Exact counts from one returned facts snapshot. No derived rate or assumed time window.
public struct MerchantInsightAttribution: Equatable {
    public struct Counts: Equatable {
        public let visitors: Int, checkins: Int, redeems: Int
        public var isEmpty: Bool { visitors == 0 && checkins == 0 && redeems == 0 }
    }
    public struct VisitorSplit: Equatable {
        public let newVisitors: Int, returningVisitors: Int
    }
    public let window: String?
    public let counts: Counts?
    public let split: VisitorSplit?
    public init(_ facts: MerchantMarketingValue) {
        if case .string(let text) = facts["window"], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { window = text }
        else { window = nil }
        func count(_ value: MerchantMarketingValue) -> Int? {
            guard case .number = value, let n = value.integer, (0...9_007_199_254_740_991).contains(n) else { return nil }
            return n
        }
        let attribution = facts["attribution"], returnedSplit = facts["split"]
        if let visitors = count(attribution["visitors"]), let checkins = count(attribution["checkins"]), let redeems = count(attribution["redeems"]) {
            counts = Counts(visitors: visitors, checkins: checkins, redeems: redeems)
        } else { counts = nil }
        if let newVisitors = count(returnedSplit["newVisitors"]), let returningVisitors = count(returnedSplit["returningVisitors"]) {
            split = VisitorSplit(newVisitors: newVisitors, returningVisitors: returningVisitors)
        } else { split = nil }
    }
}
