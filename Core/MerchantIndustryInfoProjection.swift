import Foundation

/// Full server names, not the mini short-chip aliases; this data is display-only.
public struct MerchantStoreIndustryName: Decodable, Equatable {
    public let id: Int
    public let name: String
    private enum CodingKeys: String, CodingKey { case id, categoryName }
    public init(id: Int, name: String) { self.id = id; self.name = name }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.merchantInteger(.id), id > 0 else { throw APIError.malformedResponse }
        self.id = id; name = try c.decode(String.self, forKey: .categoryName)
    }
}

/// Original info projection for basic-store editing; no cooperation permission or fields.
public struct MerchantStoreProfileAndDecor: Decodable {
    public let profile: MerchantStoreProfile
    public let decor: MerchantStoreDecor
    public init(from decoder: Decoder) throws { profile = try .init(from: decoder); decor = try .init(from: decoder) }
}
