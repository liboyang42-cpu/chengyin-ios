import Foundation

public struct ClubPostDiscussionContext: Hashable {
    public let clubID: Int
    public let identity: ClubReadIdentity
    public let readScope: UUID
    public let viewerRevision: UInt64
    public init(clubID: Int, identity: ClubReadIdentity, readScope: UUID, viewerRevision: UInt64) {
        self.clubID = clubID; self.identity = identity; self.readScope = readScope; self.viewerRevision = viewerRevision
    }
}

/// A rendered post action can only toggle the exact accepted post it displayed.
public struct ClubPostDiscussionSelection: Hashable, Identifiable {
    public let id = UUID()
    public let post: ClubCommunityPost
    public let context: ClubPostDiscussionContext
    public init?(post: ClubCommunityPost, acceptedPosts: [ClubCommunityPost], context: ClubPostDiscussionContext) {
        guard (1...9_007_199_254_740_991).contains(context.clubID), (1...9_007_199_254_740_991).contains(post.id),
              context.identity.accountID == nil || (context.identity.accountID ?? 0) > 0,
              post.clubID == nil || post.clubID == context.clubID,
              acceptedPosts.filter({ $0.id == post.id }).count == 1, acceptedPosts.contains(post) else { return nil }
        self.post = post; self.context = context
    }
    public func isCurrent(acceptedPosts: [ClubCommunityPost]?, context: ClubPostDiscussionContext) -> Bool {
        guard self.context == context, let acceptedPosts else { return false }
        return acceptedPosts.filter({ $0.id == post.id }).count == 1 && acceptedPosts.contains(post)
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Mirrors onToggleComments: one open post, repeated tap collapses, switching starts fresh.
public struct ClubPostDiscussionState {
    public private(set) var selection: ClubPostDiscussionSelection?
    public init() {}
    @discardableResult public mutating func toggle(_ target: ClubPostDiscussionSelection,
                                                  acceptedPosts: [ClubCommunityPost]?, context: ClubPostDiscussionContext) -> Bool {
        guard target.isCurrent(acceptedPosts: acceptedPosts, context: context) else { return false }
        if selection?.post == target.post && selection?.context == target.context { selection = nil }
        else { selection = target }
        return true
    }
    public mutating func close() { selection = nil }
}
