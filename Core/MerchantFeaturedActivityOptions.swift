import Foundation

/// An owned-list candidate is not proof of public visibility or permission to feature it.
public struct MerchantFeaturedActivityOption: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String?
    private enum CodingKeys: String, CodingKey { case id, name, title }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.id), (1...9_007_199_254_740_991).contains(id) else { throw APIError.malformedResponse }
        self.id = id
        let name = try c.decodeIfPresent(String.self, forKey: .name)
        let title = try c.decodeIfPresent(String.self, forKey: .title)
        self.name = name.flatMap { $0.isEmpty ? nil : $0 } ?? title.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct MerchantFeaturedActivityPage: Decodable, Equatable, Sendable {
    public static let pageSize = 20
    public let rows: [MerchantFeaturedActivityOption]
    public let total: Int?
    private enum CodingKeys: String, CodingKey { case rows, total }
    public init(from decoder: Decoder) throws {
        if let rows = try? decoder.singleValueContainer().decode([MerchantFeaturedActivityOption].self) {
            self.rows = rows; total = nil
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rows = try c.decode([MerchantFeaturedActivityOption].self, forKey: .rows)
            total = try c.decodeIfPresent(Int.self, forKey: .total)
        }
        guard rows.count <= Self.pageSize, Set(rows.map(\.id)).count == rows.count,
              total.map({ $0 >= rows.count }) ?? true else { throw APIError.malformedResponse }
    }
    public func appended(to existing: [MerchantFeaturedActivityOption]) throws -> [MerchantFeaturedActivityOption] {
        let combined = existing + rows
        guard Set(combined.map(\.id)).count == combined.count,
              total.map({ $0 >= combined.count }) ?? true,
              !rows.isEmpty || (total.map({ $0 <= combined.count }) ?? true) else { throw APIError.malformedResponse }
        return combined
    }
}
