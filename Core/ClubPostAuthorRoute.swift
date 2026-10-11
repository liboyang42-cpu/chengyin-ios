import Foundation

public struct ClubPostAuthorContext: Hashable {
    public let clubID: Int?
    public let identity: ClubReadIdentity
    public let readScope: UUID
    public let profileIdentity: SocialAccountIdentity
    public let profileRevision: UInt64
    public let profileReader: ObjectIdentifier
    public let squareReader: ObjectIdentifier
    public let squareScope: UUID
    public init(clubID: Int?, identity: ClubReadIdentity, readScope: UUID, profileIdentity: SocialAccountIdentity,
                profileRevision: UInt64, profileReader: ObjectIdentifier, squareReader: ObjectIdentifier, squareScope: UUID) {
        self.clubID = clubID; self.identity = identity; self.readScope = readScope
        self.profileIdentity = profileIdentity; self.profileRevision = profileRevision
        self.profileReader = profileReader; self.squareReader = squareReader; self.squareScope = squareScope
    }
    public var matchesViewer: Bool {
        identity.accountID == profileIdentity.accountID && identity.epoch == profileIdentity.epoch &&
        (identity.accountID == nil || (identity.accountID ?? 0) > 0) && (clubID == nil || (clubID ?? 0) > 0)
    }
}

/// P045 onPostUser uses authorMemberId, never the post ID or current account ID.
/// The public-profile reader independently validates its own response and access.
public struct ClubPostAuthorRoute: Hashable, Identifiable {
    public let id = UUID()
    public let memberID: Int
    public let context: ClubPostAuthorContext
    private let post: ClubCommunityPost
    public init?(post: ClubCommunityPost, acceptedPosts: [ClubCommunityPost], context: ClubPostAuthorContext) {
        guard context.matchesViewer, let memberID = post.authorMemberID,
              (1...9_007_199_254_740_991).contains(memberID),
              post.clubID == nil || post.clubID == context.clubID,
              acceptedPosts.filter({ $0.id == post.id }).count == 1, acceptedPosts.contains(post) else { return nil }
        self.memberID = memberID; self.context = context; self.post = post
    }
    public func isCurrent(acceptedPosts: [ClubCommunityPost]?, context: ClubPostAuthorContext) -> Bool {
        guard self.context == context, context.matchesViewer, let acceptedPosts else { return false }
        return acceptedPosts.filter({ $0.id == post.id }).count == 1 && acceptedPosts.contains(post)
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
