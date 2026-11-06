import Foundation

/// Priority-signup badge and topic count presentation for `cy-club-card` in `pages/talent/list`.
public struct ClubPriorityMemberBadge: Equatable, Sendable {
    public let prioritySignup: Bool
    public let topicCount: Int?

    public init(prioritySignup: Bool, topicCount: Int? = nil) {
        self.prioritySignup = prioritySignup
        self.topicCount = topicCount
    }

    public var badgeText: String? {
        prioritySignup ? "成员优先报名" : nil
    }

    public var topicCountText: String? {
        guard let count = topicCount, count > 0 else { return nil }
        return "\(count) 个主题"
    }
}

/// Strict response shape validator for `/api/club/home` matching the mini-program contract.
public enum ClubHomeStrictShapeCheck: Sendable {
    public static let requiredKeys: [String] = ["owned", "joined", "nearby", "leaderStatus"]

    public static func validate(jsonObject: [String: Any]) -> Bool {
        requiredKeys.allSatisfy { key in
            guard let value = jsonObject[key] else { return false }
            return !(value is NSNull)
        }
    }
}

/// Mini-program `pages/talent/list` (俱乐部 tab) facts over the existing `/api/club/home` read.
/// Presentation only. The source marks every `owned` row as owner and every `joined` row as
/// joined before drawing `cy-club-card`; rows themselves may omit those flags.
public enum ClubTabPresentation {
    public enum Section: Equatable, Sendable { case owned, joined, nearby }
    /// Source `topTabs`: 帖文 then 俱乐部, with 俱乐部 active on open.
    public enum TopTab: String, CaseIterable, Sendable {
        case feed, club
        public var key: String { self == .feed ? "club.tab.top.feed" : "club.tab.top.club" }
    }

    /// L1–L5 organiser level copy inherited by the club (level 0 shows nothing; others `Lv.N`).
    public static func levelKey(_ level: Int) -> (key: String?, fallback: String?) {
        switch level {
        case 1...5: return ("club.tab.level.\(level)", nil)
        case let value where value > 5: return (nil, "Lv.\(value)")
        default: return (nil, nil)
        }
    }

    public static func isOwner(_ club: ClubRecord, in section: Section) -> Bool { section == .owned || club.isOwner }
    public static func isJoined(_ club: ClubRecord, in section: Section) -> Bool { section == .joined || club.isJoined }

    /// Player-audience card tags: club types, keywords, then 免费加入 for a club the viewer is not in.
    /// Split exactly as the source `splitList`: a JSON string array, or `, ; 、 ， ；` separated text.
    public static func tags(_ club: ClubRecord, in section: Section) -> (labels: [String], freeToJoin: Bool) {
        var seen = Set<String>(), labels: [String] = []
        for value in splitList(club.clubType) + splitList(club.keywords) where seen.insert(value).inserted { labels.append(value) }
        return (labels, !isOwner(club, in: section) && !isJoined(club, in: section))
    }

    static func splitList(_ raw: String?) -> [String] {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return [] }
        if text.hasPrefix("[") {
            guard let data = text.data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
            return array.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        let separators = CharacterSet(charactersIn: ",;、，；")
        return text.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The source shows one list: owned → joined → nearby (merchants see only nearby).
    public static func isEmpty(_ home: ClubHome, nearby: [ClubRecord], merchant: Bool) -> Bool {
        merchant ? nearby.isEmpty : home.owned.isEmpty && home.joined.isEmpty && nearby.isEmpty
    }

    /// 还没有俱乐部 (with the 创建俱乐部 CTA) for players; 本城还没有俱乐部 for merchants.
    public static func emptyKeys(merchant: Bool) -> (title: String, detail: String, offersCreate: Bool) {
        merchant ? ("club.tab.empty.merchant", "club.tab.empty.merchant.detail", false)
                 : ("club.tab.empty", "club.tab.empty.detail", true)
    }

    /// Feed empty copy differs when the viewer has no club at all (`clubCount == 0`).
    public static func feedEmptyKeys(clubCount: Int?) -> (title: String, detail: String) {
        clubCount == 0 ? ("club.tab.feed.noClub", "club.tab.feed.noClub.detail") : ("club.tab.feed.empty", "club.tab.feed.empty.detail")
    }
}
