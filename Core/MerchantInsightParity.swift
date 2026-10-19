import Foundation

/// Source pages/merchant/marketing/ai-insight/index.js _buildValueCard: "比上期 ±N 位玩家" only when the
/// previous period has a positive count and differs; a missing previous value is not zero.
public enum MerchantInsightParity {
    public static func visitorDelta(_ facts: MerchantMarketingValue) -> Int? {
        func count(_ value: MerchantMarketingValue) -> Int? {
            guard case .number = value, let n = value.integer, n >= 0 else { return nil }
            return n
        }
        guard let current = count(facts["attribution"]["visitors"]), let previous = count(facts["attribution"]["prevVisitors"]),
              previous > 0, current != previous else { return nil }
        return current - previous
    }
}
