import Foundation

/// Java Date JSON may be text or epoch milliseconds. Never guess seconds from magnitude.
public enum ExploreCompletionTime: Decodable, Equatable {
    case text(String), milliseconds(Int64)
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(String.self) {
            guard value.utf8.count <= 128 else { throw APIError.malformedResponse }
            self = .text(value)
        } else if let value = try? c.decode(Int64.self), (0...253_402_300_799_999).contains(value) {
            self = .milliseconds(value)
        } else { throw APIError.malformedResponse }
    }
}

/// Navigation/read eligibility, not server authorization. The endpoint independently checks ownership.
public struct ExploreCompletionTarget: Hashable {
    public let registrationID: Int
    public let accountID: Int
    public init?(order: ProfileOrder, requestedID: Int, accountID: Int) {
        guard accountID > 0, requestedID > 0, order.id == requestedID, order.memberID == accountID,
              order.purchaseKind == 3, order.paymentStatus == 2 || order.registrationStatus == 2 else { return nil }
        registrationID = requestedID; self.accountID = accountID
    }
}

/// Pinned ExploreCompletionVO. These are readback facts; nothing here awards, redeems or joins.
public struct ExploreCompletionSnapshot: Decodable, Equatable {
    public static let maximumRows = 2_000
    public let registrationID: Int
    public let topicID: Int?
    public let completed: Bool
    public let requiredChapterCount: Int
    public let redeemedChapterCount: Int
    public let stamps: [Stamp]
    public let awards: Awards
    public let revisit: Revisit?
    /// A missing activity/topic mapping is a real server empty shell, never a 0/0 completion.
    public var hasTopic: Bool { topicID != nil }
    private enum CodingKeys: String, CodingKey { case registrationId, topicId, completed, requiredChapterCount, redeemedChapterCount, stamps, awards, revisit }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        registrationID = try c.decode(Int.self, forKey: .registrationId)
        topicID = try c.decodeIfPresent(Int.self, forKey: .topicId)
        completed = try c.decode(Bool.self, forKey: .completed)
        requiredChapterCount = try c.decode(Int.self, forKey: .requiredChapterCount)
        redeemedChapterCount = try c.decode(Int.self, forKey: .redeemedChapterCount)
        stamps = try c.decode([Stamp].self, forKey: .stamps)
        awards = try c.decode(Awards.self, forKey: .awards)
        revisit = try c.decodeIfPresent(Revisit.self, forKey: .revisit)
        guard registrationID > 0, topicID.map({ $0 > 0 }) ?? true,
              (0...Self.maximumRows).contains(requiredChapterCount),
              (0...requiredChapterCount).contains(redeemedChapterCount),
              stamps.count <= Self.maximumRows else { throw APIError.malformedResponse }
    }
    public struct Stamp: Decodable, Equatable {
        public let chapterID: Int
        public let title: String?
        public let obtainedAt: ExploreCompletionTime?
        public let collected: Bool
        private enum CodingKeys: String, CodingKey { case chapterId, title, obtainedAt, collected }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            chapterID = try c.decode(Int.self, forKey: .chapterId)
            title = try c.completionText(.title)
            obtainedAt = try c.decodeIfPresent(ExploreCompletionTime.self, forKey: .obtainedAt)
            collected = try c.decode(Bool.self, forKey: .collected)
            guard chapterID > 0 else { throw APIError.malformedResponse }
        }
    }
    public struct Award: Decodable, Equatable {
        public let kind: String
        public let title: String?
        public let iconURL: String?
        public let amount: Int?
        public let grantedAt: ExploreCompletionTime?
        private enum CodingKeys: String, CodingKey { case kind, title, iconUrl, amount, grantedAt }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let kind = try c.completionText(.kind, maximum: 128), !kind.isEmpty else { throw APIError.malformedResponse }
            self.kind = kind; title = try c.completionText(.title)
            iconURL = try c.completionText(.iconUrl)
            amount = try c.decodeIfPresent(Int.self, forKey: .amount)
            grantedAt = try c.decodeIfPresent(ExploreCompletionTime.self, forKey: .grantedAt)
        }
    }
    public struct Awards: Decodable, Equatable {
        public let credited: Bool
        public let points: Int?
        public let earnedXP: Int?
        public let couponGranted: Bool?
        public let items: [Award]
        private enum CodingKeys: String, CodingKey { case credited, points, earnedXp, couponGranted, items }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            credited = try c.decode(Bool.self, forKey: .credited)
            points = try c.decodeIfPresent(Int.self, forKey: .points)
            earnedXP = try c.decodeIfPresent(Int.self, forKey: .earnedXp)
            couponGranted = try c.decodeIfPresent(Bool.self, forKey: .couponGranted)
            items = try c.decode([Award].self, forKey: .items)
            guard items.count <= ExploreCompletionSnapshot.maximumRows else { throw APIError.malformedResponse }
        }
    }
    public struct Revisit: Decodable, Equatable {
        public let clubID: Int?
        public let clubName: String?
        public let clubLogo: String?
        public let clubLeaderMemberID: Int?
        public let followed: Bool
        public let joined: Bool
        public let nextEdition: NextEdition?
        private enum CodingKeys: String, CodingKey { case clubId, clubName, clubLogo, clubLeaderMemberId, followed, joined, nextEdition }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            clubID = try c.decodeIfPresent(Int.self, forKey: .clubId)
            clubLeaderMemberID = try c.decodeIfPresent(Int.self, forKey: .clubLeaderMemberId)
            clubName = try c.completionText(.clubName); clubLogo = try c.completionText(.clubLogo)
            followed = try c.decode(Bool.self, forKey: .followed); joined = try c.decode(Bool.self, forKey: .joined)
            nextEdition = try c.decodeIfPresent(NextEdition.self, forKey: .nextEdition)
            guard clubID.map({ $0 > 0 }) ?? true, clubLeaderMemberID.map({ $0 > 0 }) ?? true else { throw APIError.malformedResponse }
        }
    }
    public struct NextEdition: Decodable, Equatable {
        public let topicID: Int
        public let name: String?
        public let imageURL: String?
        public let startDate: ExploreCompletionTime?
        private enum CodingKeys: String, CodingKey { case topicId, name, imgUrl, startDate }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            topicID = try c.decode(Int.self, forKey: .topicId)
            name = try c.completionText(.name); imageURL = try c.completionText(.imgUrl)
            startDate = try c.decodeIfPresent(ExploreCompletionTime.self, forKey: .startDate)
            guard topicID > 0 else { throw APIError.malformedResponse }
        }
    }
}
private extension KeyedDecodingContainer {
    func completionText(_ key: Key, maximum: Int = 4_096) throws -> String? {
        guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard text.utf8.count <= maximum else { throw APIError.malformedResponse }
        return text
    }
}

public enum ExploreCompletionFailure: Error, Equatable {
    case rejected(code: Int, message: String?)
}
