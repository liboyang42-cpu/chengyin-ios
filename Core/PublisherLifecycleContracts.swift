import Foundation

public enum PublisherLifecycleError: Error, Equatable { case unavailable, stale, incomplete, forbidden, rejected(String) }
public enum PublisherPriceSubtype: String, CaseIterable { case guided, selfPlay = "self" }
public struct PublisherPricingInput: Equatable {
    public let topicID: Int
    public let subtype: PublisherPriceSubtype
    public let leadCost: Decimal?
    public let teamSize: Int?
    public init(topicID: Int, subtype: PublisherPriceSubtype, leadCost: Decimal? = nil, teamSize: Int? = nil) throws {
        guard topicID > 0 else { throw PublisherLifecycleError.incomplete }
        if subtype == .guided { guard let leadCost, !leadCost.isNaN, leadCost >= 0, let teamSize, teamSize > 0 else { throw PublisherLifecycleError.incomplete } }
        self.topicID = topicID; self.subtype = subtype; self.leadCost = leadCost; self.teamSize = teamSize
    }
    var fields: [String: ProjectEditJSON] {
        var result: [String: ProjectEditJSON] = ["topicId": .number(Decimal(topicID)), "subType": .string(subtype.rawValue)]
        if subtype == .guided { result["leadCost"] = leadCost.map(ProjectEditJSON.number); result["teamSize"] = teamSize.map { .number(Decimal($0)) } }
        return result
    }
}
public struct PublisherLineup: Equatable, Identifiable {
    public let type: String; public let partnerID: Int; public let mode: Int
    public let shareRate: String?; public let fixedFee: String?
    public var id: String { "\(type):\(partnerID)" }
    public var validTerms: Bool {
        switch mode {
        case 0: return true
        case 1: guard let raw = shareRate, let n = Decimal(string: raw), !n.isNaN else { return false }; return n >= 0 && n <= 100
        case 2: guard let raw = fixedFee, let n = Decimal(string: raw), !n.isNaN else { return false }; return n >= 0
        default: return false
        }
    }
    init?(_ json: ProjectEditJSON) {
        guard let b = json.object, let type = b["toType"]?.text, !type.isEmpty,
              let id = PublisherValue.integer(b["toId"]), id > 0 else { return nil }
        self.type = type; partnerID = id; mode = PublisherValue.integer(b["shareMode"]) ?? -1
        shareRate = PublisherValue.raw(b["shareRate"]); fixedFee = PublisherValue.raw(b["fixedFee"])
    }
}
public struct PublisherPricingPreview: Equatable {
    public let minimum: Decimal; public let reference: Decimal?; public let sampleSize: Int?; public let referenceLabel: String?
    public let lineup: [PublisherLineup]
    public init(_ data: ProjectEditJSON) throws {
        guard let b = data.object, let floor = PublisherValue.number(b["priceMin"]), !floor.isNaN else { throw PublisherLifecycleError.incomplete }
        minimum = floor; reference = PublisherValue.number(b["cityReferencePrice"])
        sampleSize = PublisherValue.integer(b["cityReferenceSampleSize"]); referenceLabel = b["cityReferenceLabel"]?.text
        lineup = (b["lineup"]?.array ?? []).compactMap(PublisherLineup.init)
    }
    public func accepts(_ price: Decimal) -> Bool { !price.isNaN && price >= minimum }
}
public struct PublisherXPBudget: Equatable {
    public let budget: Int?; public let totalXP: Int?; public let over: Bool?; public let overBy: Int?; public let remain: Int?
    public let nodes: [Node]
    public struct Node: Equatable, Identifiable { public let id: Int; public let name: String?; public let xp: Int? }
    public init(_ data: ProjectEditJSON) throws {
        guard let b = data.object else { throw PublisherLifecycleError.incomplete }
        budget = PublisherValue.integer(b["budget"]); totalXP = PublisherValue.integer(b["totalXp"])
        if case .bool(let value)? = b["over"] { over = value } else { over = nil }
        overBy = PublisherValue.integer(b["overBy"]); remain = PublisherValue.integer(b["remain"])
        nodes = (b["perNode"]?.array ?? []).compactMap { item in
            guard let row = item.object, let id = PublisherValue.integer(row["nodeId"]), id > 0 else { return nil }
            return Node(id: id, name: row["name"]?.text, xp: PublisherValue.integer(row["xp"]))
        }
    }
}
public struct PublisherPartnerInspection: Equatable { public let terms: PublisherLineup; public let profile: ProjectEditJSON }
/// Fresh server-backed host authority. Never manufacture from navigation IDs or local role labels.
public struct PublisherAuthority: Equatable {
    public let resource: PublishedResource; public let ownerAccountID: Int; public let revision: String; public let beta: Bool
    public let eligibleClubIDs: Set<Int>
    public init(resource: PublishedResource, ownerAccountID: Int, revision: String, beta: Bool, eligibleClubIDs: Set<Int> = []) {
        self.resource = resource; self.ownerAccountID = ownerAccountID; self.revision = revision; self.beta = beta; self.eligibleClubIDs = eligibleClubIDs
    }
}
public enum PublisherLifecycleAction: Equatable {
    case pricing(PublisherPricingInput, Decimal)
    case cancel(PublishedResource, reason: String, scope: String?)
    case transfer(topicID: Int, clubID: Int)
    case graduate(topicID: Int)
    var resource: PublishedResource? {
        switch self {
        case .pricing(let input, _): return try? PublishedResource(kind: .topic, value: input.topicID)
        case .cancel(let resource, _, _): return resource
        case .transfer(let id, _), .graduate(let id): return try? PublishedResource(kind: .topic, value: id)
        }
    }
}
public struct PublisherLifecycleReview: Equatable, Identifiable {
    public let id: UUID; public let session: PublishingSession; public let action: PublisherLifecycleAction
    public let authority: PublisherAuthority; public let preview: PublisherPricingPreview?; public let paidPlayers: Int?
    let createdAt: Date
}
public enum PublisherLifecycleOutcome: Equatable { case acknowledged(message: String?, newTopicID: Int?), rejected(String), notSent, unknown }
enum PublisherValue {
    static func number(_ value: ProjectEditJSON?) -> Decimal? { if case .number(let n)? = value { return n }; return nil }
    static func integer(_ value: ProjectEditJSON?) -> Int? { value?.integer ?? value?.text.flatMap(Int.init) }
    static func raw(_ value: ProjectEditJSON?) -> String? { value?.text ?? number(value).map { NSDecimalNumber(decimal: $0).stringValue } }
}
