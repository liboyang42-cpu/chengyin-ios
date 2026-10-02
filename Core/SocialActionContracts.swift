import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SocialActionTarget: Hashable {
    case newPost
    case member(Int)
    case post(Int)
    case comment(postID: Int, commentID: Int)
    public var postID: Int? { switch self { case .newPost, .member: return nil; case .post(let id), .comment(let id, _): return id } }
    public var memberID: Int? { if case .member(let id) = self { return id }; return nil }
    public var commentID: Int? { if case .comment(_, let id) = self { return id }; return nil }
    public var isValid: Bool { (memberID.map { $0 > 0 } ?? true) && (postID.map { $0 > 0 } ?? true) && (commentID.map { $0 > 0 } ?? true) }
}
public enum SocialPostAction: String, CaseIterable { case like = "LIKE", bookmark = "BOOKMARK" }
public enum SocialActionCommand: Equatable {
    case createPost(text: String, requestID: String)
    case editPost(text: String)
    case comment(text: String)
    case postAction(SocialPostAction, enabled: Bool, requestID: String)
    case toggleCommentLike
    case toggleFollow, startChat
    case report
    public static func newPost(text: String) -> Self { .createPost(text: text, requestID: UUID().uuidString) }
    public static func action(_ action: SocialPostAction, enabled: Bool) -> Self { .postAction(action, enabled: enabled, requestID: UUID().uuidString) }
    public var text: String? { switch self { case .createPost(let text, _), .editPost(let text), .comment(let text): return text; default: return nil } }
    public var canRetryAfterUnknown: Bool {
        // Comment creation/toggle/report source contracts have no idempotency keys. This
        // slice never retries any uncertain write, even those with request IDs.
        false
    }
    public func validate(target: SocialActionTarget, snapshot: SocialActionSnapshot, identity: SocialAccountIdentity) throws {
        guard let accountID = identity.accountID, accountID > 0 else { throw SocialActionBlock.signIn }
        guard target.isValid, snapshot.target == target else { throw SocialActionBlock.changed }
        if let text, SocialText.nonempty(text) == nil { throw SocialActionBlock.emptyText }
        switch self {
        case .toggleFollow, .startChat:
            guard let memberID = target.memberID, let profile = snapshot.profile, memberID == profile.id, memberID != accountID else { throw SocialActionBlock.invalid }
            if self == .toggleFollow, profile.isFollowed == nil { throw SocialActionBlock.changed }
        case .createPost(_, let id):
            guard target == .newPost, Self.validRequestID(id) else { throw SocialActionBlock.invalid }
        case .editPost:
            guard case .post = target, let post = snapshot.post, post.memberID == accountID else { throw SocialActionBlock.ownerRequired }
            guard post.lifecycle == "PUBLISHED" else { throw SocialActionBlock.changed }
        case .comment:
            guard let post = snapshot.post, post.viewerCanComment, post.commentPolicy != "OFF", post.lifecycle == "PUBLISHED" else { throw SocialActionBlock.commentsClosed }
            if target.commentID != nil { guard let comment = snapshot.comment, comment.lifecycle == "PUBLISHED", comment.approvalState == "VISIBLE" else { throw SocialActionBlock.changed } }
        case .postAction(_, _, let id):
            guard case .post = target, snapshot.post != nil, Self.validRequestID(id) else { throw SocialActionBlock.invalid }
        case .toggleCommentLike:
            guard target.commentID != nil, snapshot.comment != nil else { throw SocialActionBlock.changed }
        case .report:
            guard snapshot.post != nil, target.commentID == nil || snapshot.comment != nil else { throw SocialActionBlock.changed }
        }
    }
    private static func validRequestID(_ id: String) -> Bool {
        (16...64).contains(id.utf8.count) && id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
}
public struct SocialActionSnapshot: Equatable {
    public let target: SocialActionTarget
    public let post: SquarePost?
    public let comment: SquareComment?
    public let profile: SocialPublicProfile?
    public init(target: SocialActionTarget, post: SquarePost? = nil, comment: SquareComment? = nil, profile: SocialPublicProfile? = nil) { self.target = target; self.post = post; self.comment = comment; self.profile = profile }
    public func validate() throws {
        guard target.isValid else { throw SocialActionBlock.invalid }
        if let id = target.memberID { guard profile?.id == id else { throw SocialActionBlock.changed } }
        if let id = target.postID { guard post?.id == id else { throw SocialActionBlock.changed } }
        if let id = target.commentID { guard comment?.id == id else { throw SocialActionBlock.changed } }
    }
    /// Fields whose change makes the reviewed intent materially different.
    public func sameContext(as other: Self) -> Bool {
        target == other.target && profile?.id == other.profile?.id && profile?.isFollowed == other.profile?.isFollowed && post?.id == other.post?.id && post?.memberID == other.post?.memberID &&
            post?.contents == other.post?.contents && post?.dataID == other.post?.dataID && post?.dataType == other.post?.dataType &&
            post?.lifecycle == other.post?.lifecycle && post?.viewerCanComment == other.post?.viewerCanComment && post?.commentPolicy == other.post?.commentPolicy &&
            comment?.id == other.comment?.id && comment?.memberID == other.comment?.memberID && comment?.contents == other.comment?.contents && comment?.lifecycle == other.comment?.lifecycle && comment?.isLiked == other.comment?.isLiked && comment?.approvalState == other.comment?.approvalState
    }
}
public enum SocialActionBlock: Error, Equatable { case signIn, invalid, emptyText, ownerRequired, commentsClosed, changed, pending, disabled, cancelled }
public enum SocialActionAvailability: Equatable { case disabled, syntheticOnly }
public enum SocialActionWriteFailure: Error, Equatable { case notSent, rejected, outcomeUnknown }
/// An acknowledgement cannot be promoted into a published post, comment ID, or author identity.
public struct SocialActionReceipt: Equatable {
    public let synthetic: Bool
    public let followed: Bool?
    public let conversationID: Int?
    public init(synthetic: Bool, followed: Bool? = nil, conversationID: Int? = nil) {
        self.synthetic = synthetic; self.followed = followed; self.conversationID = conversationID
    }
}

/// Audited request construction only. No transport exists in this builder and production
/// action access below is hard-off. Does not register media, upload, or fabricate author fields.
public struct SocialActionRequestBuilder {
    public let configuration: APIConfiguration
    public init(configuration: APIConfiguration) { self.configuration = configuration }
    public func make(_ command: SocialActionCommand, snapshot: SocialActionSnapshot, identity: SocialAccountIdentity, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try snapshot.validate(); try command.validate(target: snapshot.target, snapshot: snapshot, identity: identity)
        var path: String, fields: [String: String]
        switch command {
        case .toggleFollow:
            guard let id = snapshot.target.memberID else { throw SocialActionBlock.invalid }
            path = "api/user/follow/action"; fields = ["follow_member_id": String(id)]
        case .startChat:
            guard let id = snapshot.target.memberID else { throw SocialActionBlock.invalid }
            path = "api/im/start"; fields = ["target_member_id": String(id)]
        case .createPost(let text, let requestID):
            path = "api/creativesquare/action"; fields = ["contents": text, "pics": "", "request_id": requestID]
        case .editPost(let text):
            guard let post = snapshot.post else { throw SocialActionBlock.changed }
            path = "api/creativesquare/action"; fields = ["id": String(post.id), "contents": text]
            // Source edit omits pics so existing media survive; association must be preserved.
            if let id = post.dataID, id > 0 { fields["data_id"] = String(id); fields["data_type"] = String(post.dataType) }
        case .comment(let text):
            guard let postID = snapshot.target.postID else { throw SocialActionBlock.invalid }
            path = "api/comment/add"; fields = ["owner_type": "3", "owner_id": String(postID), "rating": "0", "contents": text, "reply_id": String(snapshot.target.commentID ?? 0), "img_arr": ""]
        case .toggleCommentLike:
            guard let id = snapshot.target.commentID else { throw SocialActionBlock.invalid }
            path = "api/comment/like"; fields = ["id": String(id)]
        case .report:
            if let id = snapshot.target.commentID { path = "api/comment/report"; fields = ["id": String(id)] }
            else if let id = snapshot.target.postID { path = "api/creativesquare/report"; fields = ["id": String(id)] }
            else { throw SocialActionBlock.invalid }
        case .postAction(let action, let enabled, let requestID):
            guard let id = snapshot.target.postID else { throw SocialActionBlock.invalid }
            path = "api/v1/community/posts/\(id)/actions" + (enabled ? "" : "/\(action.rawValue)")
            var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: token)
            request.httpMethod = enabled ? "POST" : "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = enabled ? ["actionType": action.rawValue, "requestId": requestID, "source": "APP_SQUARE"] : ["requestId": requestID]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]); return request
        }
        return try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
    }
}
