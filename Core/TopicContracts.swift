import Foundation

// Strict field whitelist from lib/data/models/topic.dart. No answers, hidden story payload,
// booking intent or play session is decoded by this read-only module.
private struct TopicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private extension KeyedDecodingContainer where Key == TopicKey {
    func text(_ key: String) -> String? { try? decode(String.self, forKey: TopicKey(key)) }
    func int(_ key: String) -> Int? {
        if let v = try? decode(Int.self, forKey: TopicKey(key)) { return v }
        if let v = text(key) { return Int(v) }
        return nil
    }
    func number(_ key: String) -> Double? { try? decode(Double.self, forKey: TopicKey(key)) }
    func money(_ key: String) -> Decimal? { try? decode(Decimal.self, forKey: TopicKey(key)) }
    func flag(_ key: String) -> Bool {
        if let b = try? decode(Bool.self, forKey: TopicKey(key)) { return b }
        return (try? decode(Int.self, forKey: TopicKey(key))) == 1
    }
    func list<T: Decodable>(_ key: String) throws -> [T] {
        try decodeIfPresent([T].self, forKey: TopicKey(key)) ?? []
    }
    func images(_ key: String) -> [String] {
        (text(key) ?? "").split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

public struct TopicSummary: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let imageURL: String?
    public let introduction: String?
    public let minimumAmount: Decimal?
    public let startDate: String?
    public let addressName: String?
    public let isRecommend: Int
    public let betaFlag: Int
    public let isLike: Int
    public let likeCount: Int
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopicKey.self)
        id = c.int("id") ?? 0
        guard id > 0 else { throw APIError.malformedResponse }
        name = c.text("name") ?? ""
        imageURL = c.text("imgUrl") ?? c.text("picUrl")
        introduction = c.text("description") ?? c.text("subtitle") ?? c.text("introduction")
        minimumAmount = c.money("minAmout")
        startDate = c.text("startDate") ?? c.text("start_date")
        addressName = c.text("addressName")
        isRecommend = c.int("isRecommend") ?? 0
        betaFlag = c.int("betaFlag") ?? 0
        isLike = c.int("isLike") ?? 0
        likeCount = c.int("likeNum") ?? 0
    }
}

public struct TopicTemplate: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let imageURL: String?
    public let players: String?
    public let duration: Int?
    public let difficulty: String?
    public let validationMethod: Int?
    public let validationMethodText: String?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopicKey.self)
        id = c.int("id") ?? 0
        guard id > 0 else { throw APIError.malformedResponse }
        title = c.text("title") ?? ""
        imageURL = c.text("imgUrl")
        players = c.text("players")
        duration = c.int("duration")
        difficulty = c.text("difficulty")
        validationMethod = c.int("validationMethod")
        validationMethodText = c.text("validationMethodStr")
    }
}

public struct TopicMerchant: Decodable, Equatable {
    public let memberID: Int
    public let name: String
    public let businessTime: String?
    public let imageURL: String?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopicKey.self)
        let merchant = try? c.nestedContainer(keyedBy: TopicKey.self, forKey: TopicKey("mmsMerchant"))
        memberID = c.int("memberId") ?? 0
        name = merchant?.text("name") ?? c.text("name") ?? ""
        businessTime = merchant?.text("businessTime") ?? c.text("businessTime")
        imageURL = c.images("picUrl").first
    }
}

public struct TopicNode: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let description: String?
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public let businessTime: String?
    public let images: [String]
    public let template: TopicTemplate?
    public let merchants: [TopicMerchant]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopicKey.self)
        id = c.int("id") ?? 0
        guard id > 0 else { throw APIError.malformedResponse }
        name = c.text("name") ?? c.text("nodeName") ?? ""
        description = c.text("description")
        address = c.text("address")
        latitude = c.number("latitude")
        longitude = c.number("longitude")
        businessTime = c.text("businessTime")
        images = c.images("imgUrl")
        template = try c.decodeIfPresent(TopicTemplate.self, forKey: TopicKey("cmsMemberTemplate"))
        merchants = try c.list("registrationMerchantList")
    }
}

public struct TopicChapter: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let description: String?
    public let totalTimeMinutes: Int?
    public let nodes: [TopicNode]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopicKey.self)
        id = c.int("id") ?? 0
        guard id > 0 else { throw APIError.malformedResponse }
        title = c.text("title") ?? c.text("name") ?? ""
        description = c.text("description")
        totalTimeMinutes = c.int("totalTime")
        nodes = try c.list("nodes")
    }
}

public struct TopicRegistrant: Decodable, Equatable {
    public let memberID: Int
    public let nickname: String
    public let avatar: String?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopicKey.self)
        memberID = c.int("memberId") ?? 0
        nickname = c.text("nickname") ?? ""
        avatar = c.text("avatar")
    }
}

public struct TopicTicket: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let startTime: String?
    public let endTime: String?
    public let meetingPoint: String?
    public let refundRule: String?
    public let price: Decimal?
    public let remaining: Int?
    public let totalInventory: Int
    public let registrants: [TopicRegistrant]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopicKey.self)
        id = c.int("id") ?? 0
        guard id > 0 else { throw APIError.malformedResponse }
        name = c.text("name") ?? ""
        startTime = c.text("startTime")
        endTime = c.text("endTime")
        meetingPoint = c.text("meetingPoint")
        refundRule = c.text("refundRule")
        price = c.money("price")
        remaining = c.int("remainingInventory").map { min(2147483647, max(0, $0)) }
        totalInventory = c.int("totalInventory") ?? 0
        registrants = try c.list("cmsRegistrationList")
    }
}

public struct TopicComment: Decodable, Equatable {
    public let memberNickname: String
    public let createTime: String
    public let rating: Int
    public let contents: String
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TopicKey.self)
        memberNickname = c.text("memberNickname") ?? ""
        createTime = c.text("createTime") ?? ""
        rating = c.int("rating") ?? 0
        contents = c.text("contents") ?? ""
    }
}

public struct TopicDetail: Decodable, Equatable, Identifiable {
    /// Fresh source evidence stays separate from display defaults; unavailable proof stays nil.
    public let publisherAuthoritySource: PublisherTopicAuthoritySource?
    public let categoryNames: [String]
    public let initiatorName: String?
    public let initiatorAvatar: String?
    public let id: Int
    public let name: String
    public let introduction: String?
    public let subtitle: String?
    public let imageURL: String?
    public let images: [String]
    public let clubName: String?
    public let averageRating: Double?
    public let totalTimeSeconds: Int?
    public let startDate: String?
    public let endDate: String?
    public let totalMileage: Double?
    public let audioURL: String?
    public let audioDuration: Int?
    public let locationCount: Int
    public let templateCount: Int
    public let productType: Int
    public let perkSellableCapacity: Int?
    public let lifecycle: Int?
    public let selfPlay: Int?
    public let selfPlayPrice: Decimal?
    public let merchantCount: Int?
    public let isOwner: Bool
    public let betaFlag: Int
    public let merchantClosed: Bool
    public let storyLocked: Bool
    public let totalChapterCount: Int
    public let unlockedChapterCount: Int?
    public let isSignUp: Bool
    public let chapters: [TopicChapter]
    public let tickets: [TopicTicket]
    public let comments: [TopicComment]
    public init(from decoder: Decoder) throws {
        publisherAuthoritySource = try? PublisherTopicAuthoritySource(from: decoder)
        let c = try decoder.container(keyedBy: TopicKey.self)
        let categories: [TopicCategoryRecord] = try c.list("sysCategoryList")
        categoryNames = categories.compactMap(\.categoryName).filter { !$0.isEmpty }
        let collaborators: [TopicCollaboratorRecord] = try c.list("collaboratorsList")
        initiatorName = collaborators.first?.memberRealName
        initiatorAvatar = collaborators.first?.memberAvatar
        id = c.int("id") ?? 0
        guard id > 0 else { throw APIError.malformedResponse }
        name = c.text("name") ?? ""
        introduction = c.text("description") ?? c.text("subtitle") ?? c.text("introduction")
        subtitle = c.text("subtitle")
        imageURL = c.text("imgUrl") ?? c.text("picUrl")
        images = c.images("imgArr")
        clubName = c.text("clubName")
        averageRating = c.number("averageRating")
        totalTimeSeconds = c.int("totalTime")
        startDate = c.text("startDate") ?? c.text("start_date")
        endDate = c.text("endDate")
        totalMileage = c.number("totalMileage")
        audioURL = c.text("audioUrl")
        audioDuration = c.int("audioDuration")
        locationCount = c.int("locationCount") ?? 0
        templateCount = c.int("templateCount") ?? 0
        productType = c.int("productType") ?? 0
        perkSellableCapacity = c.int("perkSellableCapacity")
        lifecycle = c.int("lifecycle")
        selfPlay = c.int("selfPlay")
        selfPlayPrice = c.money("selfPlayPrice")
        merchantCount = c.int("registrationMerchantCount")
        isOwner = c.flag("isOwner")
        betaFlag = c.int("betaFlag") ?? 0
        merchantClosed = (try? c.decode(Bool.self, forKey: TopicKey("merchantClosed"))) == true
        storyLocked = c.flag("storyLocked")
        totalChapterCount = c.int("totalChapterCount") ?? 0
        unlockedChapterCount = c.int("unlockedChapterCount")
        isSignUp = c.flag("isSignUp")
        chapters = try c.list("chaptersList")
        tickets = try c.list("omsTicketList")
        comments = try c.list("commentList")
    }
}

public enum TopicAvailability: String, Equatable {
    case purchased, recruiting, pricing, merchantClosed, selfPlay, sessions
}
public extension TopicDetail {
    var lockedChapterCount: Int {
        let unlocked = max(0, unlockedChapterCount ?? chapters.count)
        // Clamp malformed negative values and avoid subtraction overflow.
        return totalChapterCount > unlocked ? totalChapterCount - unlocked : 0
    }
    var showStoryPaywall: Bool { storyLocked && lockedChapterCount > 0 }
    /// Purchased state takes priority. Merchant-closed notice is separately visible even here.
    var availability: TopicAvailability {
        if isSignUp { return .purchased }
        if lifecycle == 1 { return .recruiting }
        if lifecycle == 2 { return .pricing }
        if merchantClosed { return .merchantClosed }
        return selfPlay == 1 ? .selfPlay : .sessions
    }
    var canOfferPurchase: Bool { !merchantClosed && !isSignUp && lifecycle != 1 && lifecycle != 2 }
}

private struct TopicCategoryRecord: Decodable { let categoryName: String? }
private struct TopicCollaboratorRecord: Decodable { let memberRealName: String?; let memberAvatar: String? }
