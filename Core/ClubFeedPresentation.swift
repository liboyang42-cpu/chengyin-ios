import Foundation

/// A display-only projection of the existing signed-in governance feed. It does
/// not carry author-profile, reference, moderation, invitation or write authority.
public struct ClubFeedPost: Equatable, Identifiable {
    public let id: Int
    public let clubID: Int?
    public let nickname: String?
    public let avatar: String?
    public let content: String?
    public let images: [String]
    public let createTime: String?
    public let clubName: String?
    fileprivate let record: ClubGovernanceValue

    fileprivate init(record: ClubGovernanceValue) throws {
        guard let id = record["id"].int, id > 0 else { throw ClubGovernanceFailure.malformed }
        self.id = id; self.record = record
        clubID = ClubCustomerHistoryTopicRoute.positiveID(record["clubId"])
        nickname = Self.text(record["nickname"])
        avatar = Self.image(record["avatar"].string)
        content = Self.text(record["content"])
        clubName = Self.text(record["clubName"])
        createTime = Self.text(record["createTime"])
        // Source feed shows at most three delimited image references, in order.
        images = Array((record["images"].string ?? "").split(whereSeparator: { $0 == "," || $0 == ";" })
            .prefix(3).compactMap { Self.image(String($0)) })
    }
    private static func text(_ value: ClubGovernanceValue) -> String? {
        guard let text = value.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    /// URL screening is not an origin grant. The existing bounded anonymous media
    /// reader still owns approval, download limits, redirects and image sanitation.
    private static func image(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              value.utf8.count <= 8192, value.removingPercentEncoding != nil,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let parts = URLComponents(string: value), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.url != nil else { return nil }
        return value
    }
}

public struct ClubFeedPresentation: Equatable {
    public let clubCount: Int
    public let posts: [ClubFeedPost]
    public init(snapshot: ClubGovernanceSnapshot) throws {
        guard snapshot.operation == .feed, snapshot.scope == .init() else { throw ClubGovernanceFailure.targetChanged }
        let value = try ClubGovernanceValidation.validate(snapshot.value, operation: .feed, scope: snapshot.scope)
        guard let count = value["clubCount"].int, count >= 0, let rows = value["rows"].array else { throw ClubGovernanceFailure.malformed }
        clubCount = count; posts = try rows.map(ClubFeedPost.init(record:))
    }
}

/// Ephemeral source-club selection. Exact row, read generation, reader object,
/// account, epoch and viewer/authority revision must still match when rendering.
public struct ClubFeedClubRoute: Identifiable, Hashable {
    public let id = UUID()
    public let clubID: Int
    public let postID: Int
    public let context: ClubGovernanceReadContext
    public let snapshotGeneration: UInt64
    private let record: ClubGovernanceValue
    public init?(post: ClubFeedPost, snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext, snapshotGeneration: UInt64) {
        guard Self.valid(snapshot, context: context), let clubID = post.clubID,
              let rows = snapshot.value["rows"].array,
              rows.filter({ $0["id"].int == post.id }) == [post.record] else { return nil }
        self.clubID = clubID; postID = post.id; record = post.record
        self.context = context; self.snapshotGeneration = snapshotGeneration
    }
    public func isCurrent(snapshot: ClubGovernanceSnapshot?, context: ClubGovernanceReadContext, snapshotGeneration: UInt64) -> Bool {
        guard self.context == context, self.snapshotGeneration == snapshotGeneration,
              let snapshot, Self.valid(snapshot, context: context), let rows = snapshot.value["rows"].array else { return false }
        return rows.filter({ $0["id"].int == postID }) == [record] &&
            ClubCustomerHistoryTopicRoute.positiveID(record["clubId"]) == clubID
    }
    private static func valid(_ snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) -> Bool {
        context.operation == .feed && context.scope == .init() && context.accepts(snapshot) &&
        (context.identity?.accountID ?? 0) > 0 && context.readerIdentity != nil && context.accessIdentity != nil
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
