import Foundation

/// Source store identity comes from the authorized workbench, never a recommended target.
public struct MerchantInsightOrigin: Hashable {
    public let merchantID: Int
    public let readerScope: UUID
    public init?(merchantID: Int?, readerScope: UUID?) {
        guard let merchantID, (1...9_007_199_254_740_991).contains(merchantID), let readerScope else { return nil }
        self.merchantID = merchantID; self.readerScope = readerScope
    }
}
public struct MerchantInsightRecommendationRoute: Hashable {
    public enum Kind: String, Hashable { case topic, partner }
    public let kind: Kind
    public let targetID: Int
    public let origin: MerchantInsightOrigin
    public init?(kind: Kind, targetID: Int, origin: MerchantInsightOrigin) {
        guard (1...9_007_199_254_740_991).contains(targetID) else { return nil }
        self.kind = kind; self.targetID = targetID; self.origin = origin
    }
}
public struct MerchantInsightRecommendation: Equatable {
    public let name: String?
    public let reason: String?
    public let hostName: String?
    public let category: String?
    public let kind: MerchantInsightRecommendationRoute.Kind
    public let targetID: Int?
    public init(row: MerchantMarketingValue, kind: MerchantInsightRecommendationRoute.Kind, siblings: [MerchantMarketingValue]) {
        self.kind = kind; name = row["name"].text; reason = row["reason"].text
        hostName = row["hostName"].text; category = row["category"].text
        let key = kind == .topic ? "topicId" : "memberId"
        let id = Self.positiveID(row[key])
        targetID = id.flatMap { value in siblings.contains(row) && siblings.filter { Self.positiveID($0[key]) == value }.count == 1 ? value : nil }
    }
    public func route(origin: MerchantInsightOrigin) -> MerchantInsightRecommendationRoute? {
        targetID.flatMap { .init(kind: kind, targetID: $0, origin: origin) }
    }
    private static func positiveID(_ value: MerchantMarketingValue) -> Int? {
        if case .string(let raw) = value {
            guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        }
        guard let id = value.integer, (1...9_007_199_254_740_991).contains(id) else { return nil }; return id
    }
}

/// Put only the uniquely matched, actually loaded topic first. Never match a display name.
public struct MerchantInsightRecruitingFocus: Equatable {
    public let rows: [MerchantContentValue]
    public let matchedID: Int?
    public let unavailable: Bool
    public init(rows: [MerchantContentValue], topicID: Int?) {
        guard let topicID else { self.rows = rows; matchedID = nil; unavailable = false; return }
        let indices = rows.indices.filter { rows[$0]["id"].integer == topicID }
        guard (1...9_007_199_254_740_991).contains(topicID), indices.count == 1, let index = indices.first else {
            self.rows = rows; matchedID = nil; unavailable = true; return
        }
        self.rows = [rows[index]] + rows.enumerated().filter { $0.offset != index }.map(\.element)
        matchedID = topicID; unavailable = false
    }
}
