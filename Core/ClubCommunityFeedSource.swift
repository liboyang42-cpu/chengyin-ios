import Foundation

/// Read-only original scope, never membership or mutation authority.
public struct ClubCommunityFeedSourceContext: Equatable {
    public let identity: ClubReadIdentity
    public let viewerRevision: UInt64
    public let approvalID: UUID
    public let baseURL: URL
    public let namespace: String
    public let role: String
    public init(identity: ClubReadIdentity, viewerRevision: UInt64, approvalID: UUID,
                baseURL: URL, namespace: String, role: String) {
        self.identity = identity; self.viewerRevision = viewerRevision; self.approvalID = approvalID
        self.baseURL = baseURL; self.namespace = namespace; self.role = role
    }
}

/// Bind the actual mixed feed row, not just its original post ID or reposter.
public struct ClubCommunityFeedSource: Identifiable, Hashable {
    public let id = UUID()
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public let clubID: Int
    public let item: ClubCommunityFeedItem
    public let context: ClubCommunityFeedSourceContext
    public let generation: UUID
    public let readerIdentity: ObjectIdentifier
    public init?(item: ClubCommunityFeedItem, snapshot: ClubCommunitySnapshot,
                 context: ClubCommunityFeedSourceContext, generation: UUID, readerIdentity: ObjectIdentifier) {
        guard context.identity.isSignedIn, snapshot.postPage == nil, (snapshot.clubCount ?? 0) > 0,
              let clubID = item.post.clubID, (1...9_007_199_254_740_991).contains(clubID),
              snapshot.feedItems.filter({ $0.id == item.id }) == [item],
              snapshot.posts.filter({ $0.id == item.post.id }) == [item.post] else { return nil }
        self.clubID = clubID; self.item = item; self.context = context
        self.generation = generation; self.readerIdentity = readerIdentity
    }
    public func isCurrent(snapshot: ClubCommunitySnapshot?, context: ClubCommunityFeedSourceContext?,
                          generation: UUID, readerIdentity: ObjectIdentifier) -> Bool {
        guard context == self.context, generation == self.generation, readerIdentity == self.readerIdentity,
              let snapshot, snapshot.postPage == nil, (snapshot.clubCount ?? 0) > 0 else { return false }
        return snapshot.feedItems.filter { $0.id == item.id } == [item] &&
            snapshot.posts.filter { $0.id == item.post.id } == [item.post]
    }
}
