import Foundation

public struct ActivityTicket: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let price: Decimal?
    public let remainingInventory: Int?
    public let description: String?
    public let startTime: String?
    public let endTime: String?
    public let selfGuided: Bool?
    public let signupDeadline: String?
    /// Early UI guard mirrors the current activity create service, not a purchase grant.
    /// Zone-free timestamps use the existing Shanghai server-date parser. Missing or
    /// malformed ordinary timestamps cannot establish expiry. Self-guided tickets require
    /// a valid end timestamp. The server remains authoritative.
    public func registrationClosed(at now: Date) -> Bool {
        let end = endTime.flatMap(RegistrationWaitlistStatus.parseDeadline)
        if selfGuided == true {
            guard let end else { return true }
            if now >= end { return true }
            if let deadline = signupDeadline.flatMap(RegistrationWaitlistStatus.parseDeadline), now >= deadline { return true }
            return false
        }
        let boundary = startTime.flatMap(RegistrationWaitlistStatus.parseDeadline) ?? end
        return boundary.map { now >= $0 } ?? false
    }
    private enum CodingKeys: String, CodingKey { case id,name,price,remainingInventory,description,startTime,endTime,selfGuided,signupDeadline }
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(Int.self,forKey:.id)
        name=try c.decode(String.self,forKey:.name)
        price=try c.decodeIfPresent(Decimal.self,forKey:.price)
        remainingInventory=try c.decodeIfPresent(Int.self,forKey:.remainingInventory)
        description=try c.decodeIfPresent(String.self,forKey:.description)
        startTime=try c.decodeIfPresent(String.self,forKey:.startTime)
        endTime=try c.decodeIfPresent(String.self,forKey:.endTime)
        selfGuided=try c.decodeIfPresent(Bool.self,forKey:.selfGuided)
        signupDeadline=try c.decodeIfPresent(String.self,forKey:.signupDeadline)
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
    public let people: ActivityPeople
    public let reviews: ActivityReviews
    public let hostMemberID: Int?
    enum CodingKeys: String, CodingKey { case omsTicketList, memberId }
    public init(from decoder:Decoder) throws {
        publisherAuthoritySource = try? PublisherActivityAuthoritySource(from: decoder)
        summary=try ActivitySummary(from:decoder)
        people=try ActivityPeople(from:decoder)
        reviews=try ActivityReviews(from:decoder)
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
