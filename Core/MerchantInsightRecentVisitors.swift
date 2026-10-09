import Foundation

/// Only the existing response's four display fields; never customer IDs or contact data.
public struct MerchantInsightRecentVisitor: Equatable {
    public let nickname: String?
    public let visitCount: Int?
    public let topicName: String?
    public let lastAtText: String?
    public init?(row: MerchantMarketingValue) {
        guard row.object != nil else { return nil }
        func text(_ key: String) -> String? {
            guard case .string(let value) = row[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }; return value
        }
        nickname = text("nickname"); topicName = text("topicName"); lastAtText = text("lastAtText")
        if case .number = row["visitCount"], let count = row["visitCount"].integer, (1...9_007_199_254_740_991).contains(count) { visitCount = count }
        else { visitCount = nil }
        guard nickname != nil || topicName != nil || lastAtText != nil || visitCount != nil else { return nil }
    }
}
public enum MerchantInsightRecentVisitors: Equatable {
    case unavailable, empty
    case loaded([MerchantInsightRecentVisitor])
    public init(_ value: MerchantMarketingValue) {
        guard let rows = value.array, rows.count <= 5 else { self = .unavailable; return }
        guard !rows.isEmpty else { self = .empty; return }
        let visitors = rows.compactMap(MerchantInsightRecentVisitor.init(row:))
        guard visitors.count == rows.count else { self = .unavailable; return }
        self = .loaded(visitors)
    }
}
