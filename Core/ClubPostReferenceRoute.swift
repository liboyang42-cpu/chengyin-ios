import Foundation

public struct ClubPostReferenceContext: Hashable {
    public let clubID: Int?
    public let identity: ClubReadIdentity
    public let readScope: UUID
    public let viewerRevision: UInt64
    public init(clubID: Int?, identity: ClubReadIdentity, readScope: UUID, viewerRevision: UInt64) {
        self.clubID = clubID; self.identity = identity; self.readScope = readScope; self.viewerRevision = viewerRevision
    }
}

/// P045 onPostReference opens sportTopicId. refId may be an activity or a template;
/// it must never be guessed to be a topic. Missing topics retain the comments action.
public struct ClubPostReferenceRoute: Hashable, Identifiable {
    public enum Destination: Hashable { case topic(Int), comments }
    public let id = UUID()
    public let destination: Destination
    public let context: ClubPostReferenceContext
    private let post: ClubCommunityPost
    public init?(post: ClubCommunityPost, acceptedPosts: [ClubCommunityPost], context: ClubPostReferenceContext) {
        guard context.identity.accountID == nil || (context.identity.accountID ?? 0) > 0,
              context.clubID == nil || (context.clubID ?? 0) > 0,
              post.clubID == nil || post.clubID == context.clubID,
              acceptedPosts.filter({ $0.id == post.id }).count == 1, acceptedPosts.contains(post),
              !post.sportName.isEmpty, post.refType == 1 || !post.sportCover.isEmpty else { return nil }
        if let topicID = post.sportTopicID, (1...9_007_199_254_740_991).contains(topicID) {
            destination = .topic(topicID)
        } else {
            // The existing native comments destination needs the exact club.
            guard context.clubID != nil else { return nil }
            destination = .comments
        }
        self.context = context; self.post = post
    }
    public func isCurrent(acceptedPosts: [ClubCommunityPost]?, context: ClubPostReferenceContext) -> Bool {
        guard self.context == context, let acceptedPosts else { return false }
        return acceptedPosts.filter({ $0.id == post.id }).count == 1 && acceptedPosts.contains(post)
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
