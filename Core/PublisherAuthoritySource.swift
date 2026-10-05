import Foundation

/// Additional, immutable evidence decoded from the SAME source-backed detail response.
/// This is deliberately separate from UI defaults. A missing beta/owner flag is unknown.
/// No public value initializer permits navigation or local-role state to manufacture proof.
public struct PublisherTopicAuthoritySource: Decodable, Equatable {
    public let resourceID: Int
    public let viewerIsOwner: Bool
    public let beta: Bool
    let stableFacts: ProjectEditJSON

    public init(from decoder: Decoder) throws {
        let source = try PublisherSourceProjection.topic.read(decoder)
        guard let body = source.object,
              let id = body["id"]?.integer, id > 0,
              let owner = PublisherSourceProjection.flag(body["isOwner"]),
              let beta = body["betaFlag"]?.integer, (0...1).contains(beta),
              body["productType"]?.integer != nil,
              let name = body["name"]?.text, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let chapters = body["chaptersList"]?.array,
              body["omsTicketList"]?.array != nil,
              PublisherSourceProjection.flag(body["storyLocked"]) == false,
              let chapterCount = body["totalChapterCount"]?.integer, chapterCount >= 0,
              chapterCount == chapters.count else { throw PublisherLifecycleError.unavailable }
        // A partially unlocked response cannot stand in for the resource being transferred.
        if let unlocked = body["unlockedChapterCount"], unlocked != .null {
            guard unlocked.integer == chapterCount else { throw PublisherLifecycleError.unavailable }
        }
        resourceID = id; viewerIsOwner = owner; self.beta = beta == 1; stableFacts = source
    }
}

/// Activity owner is source memberId, never ownerId (which means activity ID in tickets).
public struct PublisherActivityAuthoritySource: Decodable, Equatable {
    public let resourceID: Int
    public let ownerAccountID: Int
    let stableFacts: ProjectEditJSON

    public init(from decoder: Decoder) throws {
        let source = try PublisherSourceProjection.activity.read(decoder)
        guard let body = source.object,
              let id = body["id"]?.integer, id > 0,
              let owner = body["memberId"]?.integer, owner > 0,
              let name = body["name"]?.text, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              body["status"]?.integer != nil, body["publishStatus"]?.integer != nil,
              body["omsTicketList"]?.array != nil else { throw PublisherLifecycleError.unavailable }
        resourceID = id; ownerAccountID = owner; stableFacts = source
    }
}

/// Exact-key whitelist of the audited detail contracts. It never decodes answers, raw
/// story blocks, tokens, registrant personal data, comments or arbitrary unknown fields.
/// Business dates/times, cancellation state, content, ticket terms and capacity are stable
/// review facts. View/like/signup/rating counters, remaining stock and audit times are not.
private indirect enum PublisherSourceProjection {
    case scalar
    case object([String: PublisherSourceProjection])
    case array(PublisherSourceProjection)

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    func read(_ decoder: Decoder) throws -> ProjectEditJSON {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { return .null }
        switch self {
        case .scalar:
            let value = try ProjectEditJSON(from: decoder)
            switch value {
            case .null, .bool, .number, .string: return value
            case .array, .object: throw PublisherLifecycleError.unavailable
            }
        case .object(let fields):
            let c = try decoder.container(keyedBy: Key.self)
            var result: [String: ProjectEditJSON] = [:]
            for (name, projection) in fields where c.contains(Key(name)) {
                result[name] = try projection.read(c.superDecoder(forKey: Key(name)))
            }
            return .object(result)
        case .array(let projection):
            var c = try decoder.unkeyedContainer()
            var rows: [ProjectEditJSON] = []
            while !c.isAtEnd { rows.append(try projection.read(c.superDecoder())) }
            return .array(rows)
        }
    }
    static func fields(_ keys: [String], nested: [String: PublisherSourceProjection] = [:]) -> Self {
        .object(Dictionary(keys.map { ($0, Self.scalar) }, uniquingKeysWith: { first, _ in first }).merging(nested, uniquingKeysWith: { _, last in last }))
    }
    static func flag(_ value: ProjectEditJSON?) -> Bool? {
        switch value {
        case .bool(let value)?: return value
        case .number(let value)? where value == 0: return false
        case .number(let value)? where value == 1: return true
        default: return nil
        }
    }
    static let template: Self = fields(["id", "title", "imgUrl", "players", "duration", "difficulty", "validationMethod", "validationMethodStr"])
    static let merchant: Self = fields(["memberId", "name", "businessTime", "picUrl"], nested: [
        "mmsMerchant": fields(["name", "businessTime"])
    ])
    static let node: Self = fields(["id", "name", "nodeName", "description", "address", "latitude", "longitude", "businessTime", "imgUrl"], nested: [
        "cmsMemberTemplate": template, "registrationMerchantList": .array(merchant)
    ])
    static let chapter: Self = fields(["id", "title", "name", "description", "totalTime"], nested: ["nodes": .array(node)])
    static let topicTicket: Self = fields(["id", "name", "startTime", "endTime", "meetingPoint", "refundRule", "price", "totalInventory"])
    static let activityTicket: Self = fields(["id", "name", "price", "startTime", "endTime", "description"])
    static let activityNode: Self = fields(["id", "title", "imgUrl", "players", "duration"])
    static let category: Self = fields(["categoryName"])
    static let collaborator: Self = fields(["memberId", "memberRealName", "memberAvatar", "nickname", "avatar"])
    static let topic: Self = fields([
        "id", "name", "isOwner", "betaFlag", "productType", "lifecycle", "selfPlay", "selfPlayPrice",
        "description", "subtitle", "introduction", "imgUrl", "picUrl", "imgArr", "clubName",
        "totalTime", "startDate", "start_date", "endDate", "totalMileage", "audioUrl", "audioDuration",
        "merchantClosed", "storyLocked", "totalChapterCount", "unlockedChapterCount"
    ], nested: ["chaptersList": .array(chapter), "omsTicketList": .array(topicTicket),
                "sysCategoryList": .array(category), "collaboratorsList": .array(collaborator)])
    static let activity: Self = fields([
        "id", "memberId", "name", "status", "publishStatus", "productType", "topicId", "clubId",
        "description", "imgUrl", "addressName", "address", "startDate", "endDate", "latitude", "longitude",
        "cancelTime", "cancelReason", "teamMode", "teamMaxMembers"
    ], nested: ["omsTicketList": .array(activityTicket), "memberTemplateList": .array(activityNode),
                "sysCategoryList": .array(category), "collaboratorsList": .array(collaborator)])
}
