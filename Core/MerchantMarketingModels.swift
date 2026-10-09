import Foundation

/// Preserve server metadata without interpreting missing values as business facts.
public enum MerchantMarketingValue: Codable, Equatable {
    case object([String: MerchantMarketingValue]), array([MerchantMarketingValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try c.decode([Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> Self { object?[key] ?? .null }
    public var object: [String: Self]? { if case .object(let v) = self { return v }; return nil }
    public var array: [Self]? { if case .array(let v) = self { return v }; return nil }
    public var text: String? {
        if case .string(let v) = self { return v }
        if case .number(let v) = self, v.isFinite { return v.rounded() == v ? String(format: "%.0f", v) : String(v) }
        return nil
    }
    public var integer: Int? {
        if case .number(let v) = self, v.isFinite, v.rounded() == v, v >= Double(Int.min), v < Double(Int.max) { return Int(v) }
        if case .string(let v) = self { return Int(v) }
        return nil
    }
    public var decimal: Double? {
        let value: Double?
        switch self { case .number(let v): value = v; case .string(let v): value = Double(v); default: value = nil }
        return value.flatMap { $0.isFinite ? $0 : nil }
    }
    public var isTrue: Bool { self == .bool(true) }
}

public enum MerchantMarketingFailure: Error, Equatable {
    case unavailable, signIn, stale, denied, malformed, invalid, locked, storage, unknown
    case rejected(Int, String?)
    public var key: String {
        switch self {
        case .unavailable: return "merchantMarketing.unavailable"
        case .signIn: return "merchantMarketing.signIn"
        case .stale: return "merchantMarketing.stale"
        case .denied: return "merchantMarketing.denied"
        case .malformed: return "merchantMarketing.malformed"
        case .invalid: return "merchantMarketing.invalid"
        case .locked: return "merchantMarketing.locked"
        case .unknown: return "merchantMarketing.unknown"
        case .storage: return "merchantMarketing.storage"
        case .rejected: return "merchantMarketing.serverError"
        }
    }
    public var serverMessage: String? { if case .rejected(_, let message) = self { return message }; return nil }
}

public struct MerchantMarketingScope: Equatable {
    public let namespace: String, accountID: Int, epoch: UInt64
    let token: String
    public init(namespace: String, accountID: Int, epoch: UInt64, token: String) throws {
        guard !namespace.isEmpty, namespace.utf8.count <= 64, accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw MerchantMarketingFailure.invalid }
        self.namespace = namespace; self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}

public struct MerchantMarketingAccess: Equatable {
    public let active: Bool, merchantID: Int?, role: String?, permissions: Set<String>
    public init(_ raw: MerchantMarketingValue) throws {
        guard case .bool(let active) = raw["active"] else { throw MerchantMarketingFailure.malformed }
        self.active = active
        guard active else { merchantID = nil; role = nil; permissions = []; return }
        guard let id = raw["merchant"]["id"].integer, id > 0,
              let role = raw["roleCode"].text,
              ["MERCHANT_OWNER", "MERCHANT_MANAGER", "MERCHANT_CHECKIN", "MERCHANT_MARKETING", "MERCHANT_FINANCE"].contains(role),
              let names = raw["permissions"].array, names.allSatisfy({ $0.text != nil }) else { throw MerchantMarketingFailure.malformed }
        merchantID = id; self.role = role; permissions = Set(names.compactMap(\.text))
    }
    public var canReadMarketing: Bool { active && permissions.contains("merchant:marketing:read") }
    public var canSettlePrediction: Bool { active && permissions.contains("merchant:project:manage") }
}

public struct MerchantMarketingDashboard: Equatable {
    public let couponCount: Int?, received: Int?, verified: Int?, topics: Int?, exploration: Int?, activities: Int?
    public let funnel: [Funnel]
    public struct Funnel: Equatable {
        public let step: String, count: Int?, rate: Double?
    }
    public init(_ raw: MerchantMarketingValue) throws {
        guard raw.object != nil else { throw MerchantMarketingFailure.malformed }
        couponCount = raw["coupons"]["couponCount"].integer; received = raw["coupons"]["received"].integer; verified = raw["coupons"]["verified"].integer
        topics = raw["content"]["topicCount"].integer; exploration = raw["content"]["freeExploreCount"].integer; activities = raw["content"]["activityCount"].integer
        funnel = (raw["funnel"].array ?? []).map { Funnel(step: $0["step"].text ?? "", count: $0["count"].integer, rate: $0["rate"].decimal) }
    }
    public var verificationRate: Double? { guard let received, received > 0, let verified else { return nil }; return Double(verified) / Double(received) }
}

/// Only this enum can be handed to a navigation host; never expose model URLs as routes.
public enum MerchantInsightDestination: Hashable {
    case topicCooperation, decoration, content
    case recommendation(MerchantInsightRecommendationRoute)
    /// The legacy AI string whitelist stays finite. Recommendation IDs are never parsed from AI type/URL text.
    public static let allCases: [Self] = [.topicCooperation, .decoration, .content]
    public init?(rawValue: String) {
        switch rawValue { case "topic_coop": self = .topicCooperation; case "decor": self = .decoration
        case "content": self = .content; default: return nil }
    }
    public var sourcePath: String {
        switch self {
        case .topicCooperation: return "/merchant/coop"; case .decoration: return "/merchant/decor"; case .content: return "/publish/pro"
        case .recommendation(let route): return route.kind == .topic ? "/merchant/coop" : "/merchant/home"
        }
    }
}
public struct MerchantMarketingInsight: Equatable {
    public let facts: MerchantMarketingValue, ai: MerchantMarketingValue?, metadata: MerchantMarketingValue
    public let aiError: String?, generatedAt: String?
    public let recommendedTopics: [MerchantMarketingValue], recommendedPartners: [MerchantMarketingValue]
    public struct Suggestion: Equatable {
        public let title: String, reason: String?, timeSlot: String?, audience: String?, destination: MerchantInsightDestination?
    }
    public let suggestions: [Suggestion]
    public init(_ raw: MerchantMarketingValue) throws {
        guard raw["facts"].object != nil else { throw MerchantMarketingFailure.malformed }
        facts = raw["facts"]; ai = raw["ai"].object == nil ? nil : raw["ai"]; metadata = raw
        aiError = raw["aiError"].text; generatedAt = raw["generatedAt"].text
        recommendedTopics = raw["recommendedTopics"].array ?? []; recommendedPartners = raw["recommendedPartners"].array ?? []
        suggestions = (raw["ai"]["suggestions"].array ?? []).map {
            Suggestion(title: $0["title"].text ?? "", reason: $0["reason"].text, timeSlot: $0["timeSlot"].text, audience: $0["audience"].text, destination: MerchantInsightDestination(rawValue: $0["type"].text ?? ""))
        }
    }
}

public struct MerchantMarketingEntitlement: Equatable {
    public let subscriptionType: String, endDate: String?, maxUsage: Int?, usedCount: Int?
    public var isPermanent: Bool { endDate == nil }
    public init(_ raw: MerchantMarketingValue) throws {
        guard raw.object != nil, let type = raw["subscriptionType"].text else { throw MerchantMarketingFailure.malformed }
        guard raw["endDate"] == .null || raw["endDate"].text != nil else { throw MerchantMarketingFailure.malformed }
        subscriptionType = type; endDate = raw["endDate"].text; maxUsage = raw["maxUsage"].integer; usedCount = raw["usedCount"].integer
    }
}
public struct MerchantMarketingCommerce: Equatable {
    public let raw: MerchantMarketingValue
    public struct Quota: Equatable { public let limit: Int?, used: Int?, remaining: Int? }
    public var premiumTemplate: Quota? { quota("premiumTemplate") }
    public var cityNode: Quota? { quota("cityNode") }
    public var selfCheckoutEnabledByServer: Bool { raw["selfCheckoutEnabled"].isTrue }
    /// Source explicitly excludes iOS digital-entitlement checkout. No purchase API here.
    public var iOSCheckoutAvailable: Bool { false }
    public init(_ raw: MerchantMarketingValue) throws { guard raw.object != nil else { throw MerchantMarketingFailure.malformed }; self.raw = raw }
    private func quota(_ key: String) -> Quota? {
        guard raw[key].object != nil else { return nil }
        return Quota(limit: raw[key]["limit"].integer, used: raw[key]["used"].integer, remaining: raw[key]["remaining"].integer)
    }
}

public struct MerchantPredictionRound: Equatable, Identifiable {
    public let nodeID: String, playDay: String, nodeName: String?, question: String?, options: [Option], betCount: Int?, daysLeft: Int?
    public var id: String { "\(nodeID):\(playDay)" }
    public struct Option: Equatable, Identifiable { public let key: String, label: String; public var id: String { key } }
    public init(_ raw: MerchantMarketingValue) throws {
        guard let id = raw["nodeId"].integer, id > 0, let day = raw["playDay"].text, !day.isEmpty, day.utf8.count <= 32,
              let options = raw["options"].array else { throw MerchantMarketingFailure.malformed }
        nodeID = String(id); playDay = day; nodeName = raw["nodeName"].text; question = raw["question"].text
        self.options = try options.map {
            guard let key = $0["key"].text, !key.isEmpty, let label = $0["label"].text else { throw MerchantMarketingFailure.malformed }
            return Option(key: key, label: label)
        }
        guard Set(self.options.map(\.key)).count == self.options.count else { throw MerchantMarketingFailure.malformed }
        betCount = raw["betCount"].integer; daysLeft = raw["daysLeft"].integer
    }
}

public struct MerchantPredictionReview: Equatable, Identifiable {
    public let id: UUID, scope: MerchantMarketingScope, access: MerchantMarketingAccess, round: MerchantPredictionRound, option: MerchantPredictionRound.Option
    // Only the service issues reviews after fresh server access and inbox validation.
    init(scope: MerchantMarketingScope, access: MerchantMarketingAccess, round: MerchantPredictionRound, option: MerchantPredictionRound.Option) {
        id = UUID(); self.scope = scope; self.access = access; self.round = round; self.option = option
    }
}
public struct MerchantPredictionAcknowledgement: Equatable { public let winners: Int }
