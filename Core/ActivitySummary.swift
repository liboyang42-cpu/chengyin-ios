import Foundation

public enum ActivityLikeState: Int, Decodable { case none = 0, liked = 1, disliked = 2 }

/// Read-only activity fields verified against the retained Flutter client source.
/// Preserve missing price/time/location rather than inventing free tickets or a coordinate.
public struct ActivitySummary: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String?
    public let imageURL: String?
    public let addressName: String?
    public let address: String?
    public let minimumAmount: Decimal?
    public let startDate: String?
    public let endDate: String?
    public let latitude: Double?
    public let longitude: Double?
    public let productType: Int?
    public let topicID: Int?
    public let likeState: ActivityLikeState
    enum CodingKeys: String, CodingKey {
        case id, name, description, imgUrl, addressName, address, minAmout
        case startDate, endDate, latitude, longitude, productType, topicId, isLiked
    }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(Int.self,forKey:.id)
        guard id > 0 else { throw APIError.malformedResponse }
        name=try c.decode(String.self,forKey:.name)
        description=try c.decodeIfPresent(String.self,forKey:.description)
        imageURL=try c.decodeIfPresent(String.self,forKey:.imgUrl)
        addressName=try c.decodeIfPresent(String.self,forKey:.addressName)
        address=try c.decodeIfPresent(String.self,forKey:.address)
        // Wire spelling is deliberately minAmout, not minAmount.
        minimumAmount=try c.decodeIfPresent(Decimal.self,forKey:.minAmout)
        startDate=try c.decodeIfPresent(String.self,forKey:.startDate)
        endDate=try c.decodeIfPresent(String.self,forKey:.endDate)
        func number(_ key:CodingKeys) -> Double? {
            if let value=try? c.decode(Double.self,forKey:key) { return value }
            if let value=try? c.decode(String.self,forKey:key) { return Double(value) }
            return nil
        }
        func integer(_ key:CodingKeys) -> Int? {
            if let value=try? c.decode(Int.self,forKey:key) { return value }
            if let value=try? c.decode(String.self,forKey:key) { return Int(value) }
            return nil
        }
        latitude=number(.latitude);longitude=number(.longitude)
        productType=integer(.productType);topicID=integer(.topicId)
        likeState=ActivityLikeState(rawValue:integer(.isLiked) ?? 0) ?? .none
    }
    public var hasValidCoordinates: Bool {
        guard let latitude, let longitude else { return false }
        return latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
    /// A zero minimum is only a listed starting price, not proof that all tickets are free.
    public var hasZeroStartingPrice: Bool { minimumAmount == Decimal.zero }
}

/// Decode supported server list envelopes, without turning failure into a successful empty list.
public struct ActivityListResponse: Decodable {
    public let rows: [ActivitySummary]
    private enum CodingKeys: String, CodingKey { case code, data, rows }
    private struct Page: Decodable { let rows: [ActivitySummary] }
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        let code=try c.decode(Int.self,forKey:.code)
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw APIError.businessCode(code) }
        if c.contains(.data), !(try c.decodeNil(forKey:.data)) {
            rows=try c.decode(Page.self,forKey:.data).rows
        } else {
            rows=try c.decode([ActivitySummary].self,forKey:.rows)
        }
    }
}
