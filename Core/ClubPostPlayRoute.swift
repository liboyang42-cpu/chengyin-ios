import Foundation

public struct ClubPostPlayContext: Hashable {
    public let clubID: Int?
    public let identity: ClubReadIdentity
    public let readScope: UUID
    public let hostIdentifier: ObjectIdentifier?
    public let viewerRevision: UInt64
    public init(clubID: Int?, identity: ClubReadIdentity, readScope: UUID,
                hostIdentifier: ObjectIdentifier?, viewerRevision: UInt64) {
        self.clubID = clubID; self.identity = identity; self.readScope = readScope
        self.hostIdentifier = hostIdentifier; self.viewerRevision = viewerRevision
    }
}

/// Mini onPostReferencePlay routes sportTopicId to gameplay, not topic details,
/// an activity, template remix, purchase, or a locally manufactured run.
public struct ClubPostPlayRoute: Hashable, Identifiable {
    public enum Destination: Hashable { case gameplay(PlaySessionScope), comments }
    public let id = UUID()
    public let destination: Destination
    public let context: ClubPostPlayContext
    private let post: ClubCommunityPost
    /// normalizeClubPost forces completion for refType 1. The shared card renders
    /// Try for the remaining cover cards; isTopicTemplate only controls remix.
    public static func showsTryAction(for post: ClubCommunityPost) -> Bool {
        !post.sportName.isEmpty && !post.sportCover.isEmpty && post.refType != 1
    }
    public init?(post: ClubCommunityPost, acceptedPosts: [ClubCommunityPost], context: ClubPostPlayContext) {
        guard Self.showsTryAction(for: post),
              context.identity.accountID == nil || (context.identity.accountID ?? 0) > 0,
              context.clubID == nil || (context.clubID ?? 0) > 0,
              post.clubID == nil || post.clubID == context.clubID,
              acceptedPosts.filter({ $0.id == post.id }).count == 1, acceptedPosts.contains(post) else { return nil }
        if let topicID = post.sportTopicID, (1...9_007_199_254_740_991).contains(topicID) {
            destination = .gameplay(.topic(topicID))
        } else {
            guard context.clubID != nil else { return nil }
            destination = .comments
        }
        self.context = context; self.post = post
    }
    public func isCurrent(acceptedPosts: [ClubCommunityPost]?, context: ClubPostPlayContext) -> Bool {
        guard self.context == context, let acceptedPosts else { return false }
        return acceptedPosts.filter({ $0.id == post.id }).count == 1 && acceptedPosts.contains(post)
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
