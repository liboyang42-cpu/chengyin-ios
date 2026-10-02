import Foundation

public struct ActivityTicket: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let price: Decimal?
    public let remainingInventory: Int?
    public let description: String?
    private enum CodingKeys: String, CodingKey { case id,name,price,remainingInventory,description }
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(Int.self,forKey:.id)
        name=try c.decode(String.self,forKey:.name)
        price=try c.decodeIfPresent(Decimal.self,forKey:.price)
        remainingInventory=try c.decodeIfPresent(Int.self,forKey:.remainingInventory)
        description=try c.decodeIfPresent(String.self,forKey:.description)
        guard id > 0, price.map({ $0 >= .zero }) ?? true else { throw APIError.malformedResponse }
    }
    public var isSoldOut: Bool { remainingInventory.map { $0 <= 0 } ?? false }
    public var isConfirmedFree: Bool { price == Decimal.zero }
}

public struct ActivityDetail: Decodable, Equatable {
    /// Fresh source evidence stays separate from display defaults; unavailable proof stays nil.
    public let publisherAuthoritySource: PublisherActivityAuthoritySource?
    public let summary: ActivitySummary
    public let tickets: [ActivityTicket]
    public let hostMemberID: Int?
    enum CodingKeys: String, CodingKey { case omsTicketList, memberId }
    public init(from decoder:Decoder) throws {
        publisherAuthoritySource = try? PublisherActivityAuthoritySource(from: decoder)
        summary=try ActivitySummary(from:decoder)
        let c=try decoder.container(keyedBy:CodingKeys.self)
        tickets=try c.decodeIfPresent([ActivityTicket].self,forKey:.omsTicketList) ?? []
        hostMemberID=try c.decodeIfPresent(Int.self,forKey:.memberId)
    }
}

public enum ActivityDetailAccess: Decodable, Equatable {
    case allowed(ActivityDetail)
    case clubRequired(clubID: Int?, message: String?)
    enum CodingKeys: String, CodingKey { case gate, clubId, message }
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        if try c.decodeIfPresent(Bool.self,forKey:.gate) == true {
            let numeric=try? c.decode(Int.self,forKey:.clubId)
            let text=try? c.decode(String.self,forKey:.clubId)
            let id=numeric ?? text.flatMap(Int.init)
            self = .clubRequired(clubID:id.flatMap { $0 > 0 ? $0 : nil },message:try c.decodeIfPresent(String.self,forKey:.message))
        } else { self = .allowed(try ActivityDetail(from:decoder)) }
    }
}
