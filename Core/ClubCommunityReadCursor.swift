import Foundation
import CoreFoundation

/// Row identity belongs to the feed item; actions still target the embedded original post.
public struct ClubCommunityFeedItem: Equatable, Identifiable {
    public let id: String
    public let post: ClubCommunityPost
    public let repostID: Int?
    public let reposterMemberID: Int?
    public let reposterName: String
    public let repostTime: String
    public var isRepost: Bool { repostID != nil }
    public static func original(_ post: ClubCommunityPost) -> Self {
        .init(id: "p\(post.id)", post: post, repostID: nil, reposterMemberID: nil, reposterName: "", repostTime: "")
    }
    init(row: [String: Any], clubID: Int?) throws {
        if let kind = row["itemType"], !(kind is NSNull) {
            guard kind as? String == "repost", let nested = row["post"] as? [String: Any],
                  let repostID = Self.positiveID(row["repostId"]),
                  let memberID = Self.positiveID(row["reposterMemberId"]),
                  Self.positiveID(nested["id"]) != nil, Self.positiveID(nested["clubId"]) != nil else { throw ClubCommunityFailure.invalid }
            id = "r\(repostID)"; self.repostID = repostID; reposterMemberID = memberID
            post = try ClubCommunityPost(json: nested)
            reposterName = CCWire.text(row["reposterNick"]); repostTime = CCWire.text(row["repostTime"])
        } else {
            guard Self.positiveID(row["id"]) != nil, let actualClub = Self.positiveID(row["clubId"]) else { throw ClubCommunityFailure.invalid }
            guard clubID == nil || actualClub == clubID else { throw ClubCommunityFailure.stale }
            guard let pinned = row["isPinned"] as? NSNumber,
                  [0, 1].contains(pinned.intValue), pinned.doubleValue == Double(pinned.intValue) else { throw ClubCommunityFailure.invalid }
            self = .original(try ClubCommunityPost(json: row))
        }
    }
    private init(id: String, post: ClubCommunityPost, repostID: Int?, reposterMemberID: Int?, reposterName: String, repostTime: String) {
        self.id = id; self.post = post; self.repostID = repostID; self.reposterMemberID = reposterMemberID
        self.reposterName = reposterName; self.repostTime = repostTime
    }
    private static func positiveID(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue > 0, number.doubleValue <= 9_007_199_254_740_991,
              number.doubleValue.rounded(.towardZero) == number.doubleValue else { return nil }
        return number.intValue
    }
}

/// Facts are captured before content filtering. Reposts never define page depth or cursor.
public struct ClubCommunityPostPage: Equatable {
    public let clubID: Int
    public let beforeID: Int?
    public let limit: Int
    public let items: [ClubCommunityFeedItem]
    public let unpinnedIDs: [Int]
    public init(clubID: Int, beforeID: Int?, limit: Int, rows: [[String: Any]]) throws {
        guard clubID > 0, (1...50).contains(limit), beforeID.map({ $0 > 0 }) ?? true else { throw ClubCommunityFailure.invalid }
        let items = try rows.map { try ClubCommunityFeedItem(row: $0, clubID: clubID) }
        guard Set(items.map(\.id)).count == items.count else { throw ClubCommunityFailure.invalid }
        let originals = items.filter { !$0.isRepost }
        let ids = originals.filter { !$0.post.pinned }.map { $0.post.id }
        guard ids.count <= limit, originals.filter({ $0.post.pinned }).count <= limit,
              beforeID.map({ cursor in ids.allSatisfy { $0 < cursor } }) ?? true else { throw ClubCommunityFailure.invalid }
        self.clubID = clubID; self.beforeID = beforeID; self.limit = limit; self.items = items; unpinnedIDs = ids
    }
    public func snapshot() throws -> ClubCommunitySnapshot { try Self.snapshot(items: items, page: self) }
    static func snapshot(items: [ClubCommunityFeedItem], page: Self?, clubCount: Int? = nil) throws -> ClubCommunitySnapshot {
        var originals: [Int: ClubCommunityPost] = [:], ordered: [ClubCommunityPost] = []
        for item in items {
            if let existing = originals[item.post.id] {
                // Do not choose one conflicting version as an action proof.
                guard existing == item.post else { throw ClubCommunityFailure.stale }
            } else {
                originals[item.post.id] = item.post
                ordered.append(item.post)
            }
        }
        let visible = items.filter { $0.isRepost || $0.post.hasContent }
        let visibleIDs = Set(visible.map { $0.post.id })
        return .init(posts: ordered.filter { visibleIDs.contains($0.id) }, comments: [], history: [], clubCount: clubCount, postPage: page, feedItems: visible)
    }
}

/// One accepted account/epoch + club. Failed acceptance never partially mutates the cursor.
public struct ClubCommunityReadCursor {
    public private(set) var identity: ClubReadIdentity?
    public private(set) var clubID: Int?
    public private(set) var beforeID: Int?
    public private(set) var hasMore = false
    private var items: [ClubCommunityFeedItem] = []
    public init() {}
    public mutating func reset() { self = .init() }
    public mutating func accept(_ snapshot: ClubCommunitySnapshot, identity: ClubReadIdentity) throws -> ClubCommunitySnapshot {
        guard let page = snapshot.postPage else { throw ClubCommunityFailure.invalid }
        var next = self
        if let cursor = page.beforeID {
            guard next.identity == identity, next.clubID == page.clubID, next.hasMore, next.beforeID == cursor else { throw ClubCommunityFailure.stale }
        } else { next.reset(); next.identity = identity; next.clubID = page.clubID }
        var seen = Set(next.items.map(\.id))
        for item in page.items where page.beforeID == nil || item.isRepost || !item.post.pinned {
            if seen.insert(item.id).inserted { next.items.append(item) }
        }
        next.beforeID = page.unpinnedIDs.min()
        next.hasMore = page.unpinnedIDs.count >= page.limit && next.beforeID != nil
        let result = try ClubCommunityPostPage.snapshot(items: next.items, page: page)
        self = next
        return result
    }
}
