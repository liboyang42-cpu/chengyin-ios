import Foundation

/// Public-profile projection deliberately omits balances, contact handles and private account fields.
public struct SocialPublicProfile: Decodable, Equatable, Identifiable {
    public let id: Int
    public let nickname: String?
    public let avatar: String?
    public let introduction: String?
    public let level: Int?
    public let following: Int?
    public let followers: Int?
    public let likes: Int?
    public let topics: Int?
    public let activities: Int?
    public let isFollowed: Bool?
    public let interests: [SocialInterest]
    public let workImages: [String]
    public var published: Int? {
        guard let topics, let activities else { return nil }
        let sum = topics.addingReportingOverflow(activities)
        return sum.overflow ? nil : sum.partialValue
    }
    public init(from decoder: Decoder) throws {
        let v = try SocialValue(from: decoder)
        guard let id = v["id"].integer, id > 0 else { throw APIError.malformedResponse }
        self.id = id; nickname = v["nickname"].text; avatar = v["avatar"].text
        introduction = v["introduction"].text; level = v["levelId"].integer
        following = v["followNum"].integer; followers = v["fansNum"].integer
        likes = v["likeNum"].integer; topics = v["topicNum"].integer; activities = v["activityNum"].integer
        isFollowed = v["isFollow"].flag
        interests = (v["sysCategoryList"].array ?? []).compactMap {
            guard let id = $0["id"].integer, id > 0, let name = $0["categoryName"].text ?? $0["name"].text else { return nil }
            return SocialInterest(id: id, name: name)
        }
        workImages = (v["casePics"].text ?? "").split(separator: ";").compactMap { SocialText.nonempty(String($0)) }
    }
}
public struct SocialInterest: Equatable, Identifiable { public let id: Int; public let name: String }
public struct SocialInformation: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let subtitle: String?
    public let contents: String?
    public var summary: String? { SocialText.nonempty(subtitle).flatMap { $0 == title.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : $0 } }
    public var isUsable: Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return id > 0 && !title.isEmpty && SocialText.nonempty(contents) != nil &&
            (!title.utf8.allSatisfy { (48...57).contains($0) } || summary != nil)
    }
    public var isRemoved: Bool { id <= 0 }
    public init(from decoder: Decoder) throws {
        let v = try SocialValue(from: decoder)
        guard v.object != nil else { throw APIError.malformedResponse }
        id = v["id"].integer ?? 0; title = v["title"].text ?? ""
        subtitle = v["subtitle"].text; contents = v["contents"].text
    }
}
public enum SocialGuideDestination: String, CaseIterable { case home, roam }
public enum SocialGuideMode: String, CaseIterable, Identifiable {
    case classic, free, roam
    public var id: String { rawValue }
    public var destination: SocialGuideDestination { self == .roam ? .roam : .home }
}
public struct SocialInvitedMember: Decodable, Equatable, Identifiable {
    public let id: Int
    public let nickname: String?
    public let avatar: String?
    public let createdAt: String?
    public init(from decoder: Decoder) throws {
        let v = try SocialValue(from: decoder)
        guard let id = v["id"].integer, id > 0 else { throw APIError.malformedResponse }
        self.id = id; nickname = v["nickname"].text; avatar = v["avatar"].text; createdAt = v["createTime"].text
    }
}
public struct SocialInvitePage: Equatable {
    public let members: [SocialInvitedMember]
    public let total: Int?
    public let pageNumber: Int
    public let pageSize: Int
    public init(members: [SocialInvitedMember], total: Int?, pageNumber: Int, pageSize: Int) {
        self.members = members; self.total = total; self.pageNumber = pageNumber; self.pageSize = pageSize
    }
}
public struct SocialInviteReward: Equatable {
    public let points: Decimal
    public let createdAt: String?
}
public struct SocialRewardScan: Decodable, Equatable {
    public let rewards: [String: SocialInviteReward]
    public let fetchedCount: Int
    public let total: Int?
    public var isComplete: Bool { total.map { $0 <= fetchedCount } ?? false }
    public init(from decoder: Decoder) throws {
        let v = try SocialValue(from: decoder)
        guard let rows = v["rows"].array else { throw APIError.malformedResponse }
        fetchedCount = rows.count; total = v["total"].integer
        guard v["total"].isNull || total != nil else { throw APIError.malformedResponse }
        guard total.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        var result: [String: SocialInviteReward] = [:]
        for row in rows where row["eventType"].integer == 5 {
            guard let key = SocialText.normalizedID(row["eventId"].text), let amount = row["changePoints"].decimal, amount > 0 else { continue }
            let previous = result[key]
            let points = (previous?.points ?? 0) + amount
            guard !points.isNaN else { throw APIError.malformedResponse }
            result[key] = SocialInviteReward(points: points, createdAt: previous?.createdAt ?? row["createTime"].text)
        }
        rewards = result
    }
}
public enum SocialInviteRewardStatus: Equatable { case earned(SocialInviteReward), pendingFirstPurchase, notSynchronized }
public struct SocialInviteHistory: Equatable {
    public let page: SocialInvitePage
    /// nil means ledger read failed, not zero earnings.
    public let rewardScan: SocialRewardScan?
    public init(page: SocialInvitePage, rewardScan: SocialRewardScan?) { self.page = page; self.rewardScan = rewardScan }
    public var rewardsReady: Bool { rewardScan?.isComplete == true }
    public func status(for member: SocialInvitedMember) -> SocialInviteRewardStatus {
        if let reward = rewardScan?.rewards[String(member.id)] { return .earned(reward) }
        return rewardsReady ? .pendingFirstPurchase : .notSynchronized
    }
}
public struct SocialInvitePagination {
    public private(set) var members: [SocialInvitedMember] = []
    public private(set) var total: Int?
    public private(set) var nextPage = 1
    public private(set) var hasMore = true
    public private(set) var continuationInvalid = false
    public init() {}
    public mutating func accept(_ page: SocialInvitePage) throws {
        guard hasMore, page.pageNumber == nextPage, page.pageSize > 0 else { throw APIError.invalidRequest }
        var ids = Set(members.map(\.id))
        let unique = page.members.filter { ids.insert($0.id).inserted }
        members += unique; total = page.total
        let expectedMore = page.total.map { members.count < $0 } ?? (page.members.count >= page.pageSize)
        continuationInvalid = expectedMore && unique.isEmpty
        hasMore = expectedMore && !continuationInvalid && nextPage < Int.max
        if nextPage < Int.max { nextPage += 1 }
    }
}
public enum SocialAccountFailure: Error, Equatable { case rejected(code: Int, message: String?), memberUnavailable }
public enum SocialText {
    public static func nonempty(_ text: String?) -> String? {
        guard let v = text?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }; return v
    }
    public static func normalizedID(_ raw: String?) -> String? {
        guard let raw = nonempty(raw), raw.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let trimmed = String(raw.drop(while: { $0 == "0" }))
        return trimmed.isEmpty ? nil : trimmed
    }
}
/// Small strict wire projection. Arbitrary response content is never persisted or logged.
indirect enum SocialValue: Decodable {
    case object([String: Self]), array([Self]), string(String), number(Decimal), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Decimal.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let o = try? c.decode([String: Self].self) { self = .object(o) }
        else { self = .array(try c.decode([Self].self)) }
    }
    var object: [String: Self]? { if case .object(let v) = self { return v }; return nil }
    var array: [Self]? { if case .array(let v) = self { return v }; return nil }
    subscript(_ key: String) -> Self { object?[key] ?? .null }
    var text: String? {
        switch self { case .string(let s): return SocialText.nonempty(s)
        case .number(let n): return NSDecimalNumber(decimal: n).stringValue
        default: return nil }
    }
    var isNull: Bool { if case .null = self { return true }; return false }
    var integer: Int? {
        guard let text else { return nil }
        if let integer = Int(text) { return integer }
        // Source total accepts numeric strings such as "240.0". Require an exact
        // integral value; malformed totals must never mean a complete ledger.
        guard text.range(of: "^[+-]?[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return Int(NSDecimalNumber(decimal: decimal).stringValue)
    }
    var decimal: Decimal? { text.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } }
    var flag: Bool? {
        if case .bool(let value) = self { return value }
        if integer == 1 { return true }; if integer == 0 { return false }; return nil
    }
}
