import Foundation

public enum ClubCommunityFailure: Error, Equatable {
    case invalid, unavailable, stale, forbidden, rejected(Int), unknown, locked
}

public struct ClubCommunityPost: Equatable, Identifiable {
    public let id: Int, clubID: Int?, authorMemberID: Int?, version: Int, type: Int
    public let content: String, images: [String], nickname: String, createTime: String
    public let liked: Bool, pinned: Bool, edited: Bool, viewerCanManage: Bool
    public let likeCount: Int, commentCount: Int
    public let refType: Int?, refID: Int?, sportTopicID: Int?
    public let sportName: String, sportCover: String
    public let isTopicTemplate: Bool
    public var hasContent: Bool { !content.isEmpty || !images.isEmpty || (!sportName.isEmpty && (refType == 1 || !sportCover.isEmpty)) }
    public var navigableTopicID: Int? { guard let id = sportTopicID, id > 0 else { return nil }; return id }
    public init(json: [String: Any]) throws {
        guard let id = json["id"] as? Int, id > 0 else { throw ClubCommunityFailure.invalid }
        self.id = id; clubID = json["clubId"] as? Int; authorMemberID = json["authorMemberId"] as? Int
        version = (json["version"] as? Int) ?? 0; type = (json["type"] as? Int) ?? 0
        content = CCWire.text(json["content"]); images = CCWire.images(json["images"])
        nickname = CCWire.text(json["nickname"]); createTime = CCWire.text(json["createTime"])
        liked = CCWire.bool(json["liked"]); pinned = CCWire.bool(json["isPinned"])
        edited = CCWire.bool(json["edited"]); viewerCanManage = CCWire.bool(json["viewerCanManage"])
        likeCount = (json["likeCount"] as? Int) ?? 0; commentCount = (json["commentCount"] as? Int) ?? 0
        refType = json["refType"] as? Int; refID = json["refId"] as? Int; sportTopicID = json["sportTopicId"] as? Int
        sportName = CCWire.text(json["sportName"]); sportCover = CCWire.text(json["sportCover"]); isTopicTemplate = CCWire.bool(json["isTopicTemplate"])
    }
}
public struct ClubCommunityComment: Equatable, Identifiable {
    public let id: Int, postID: Int?, memberID: Int?
    public let content: String, nickname: String, createTime: String
    public init(json: [String: Any]) throws {
        guard let id = json["id"] as? Int, id > 0 else { throw ClubCommunityFailure.invalid }
        self.id = id; postID = json["postId"] as? Int; memberID = json["memberId"] as? Int
        content = CCWire.text(json["content"]); nickname = CCWire.text(json["nickname"]); createTime = CCWire.text(json["createTime"])
    }
}
/// Public snapshots intentionally exclude editor/moderator identity.
public struct ClubCommunityRevision: Equatable, Identifiable {
    public let id: Int, snapshotVersion: Int
    public let content: String, images: [String], createTime: String
    public init(json: [String: Any]) throws {
        guard let id = json["id"] as? Int, id > 0 else { throw ClubCommunityFailure.invalid }
        self.id = id; snapshotVersion = (json["snapshotVersion"] as? Int) ?? 0
        content = CCWire.text(json["content"]); images = CCWire.images(json["images"]); createTime = CCWire.text(json["createTime"])
    }
}
enum CCWire {
    static func text(_ value: Any?) -> String { ((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    static func bool(_ value: Any?) -> Bool { (value as? Bool == true) || (value as? Int == 1) }
    static func images(_ value: Any?) -> [String] { text(value).split(separator: ";").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    static func rows(_ value: Any?) throws -> [[String: Any]] {
        if let rows = value as? [[String: Any]] { return rows }
        if let object = value as? [String: Any], let rows = object["rows"] as? [[String: Any]] { return rows }
        throw ClubCommunityFailure.invalid
    }
}
public struct ClubCommunitySession: Equatable {
    public let identity: ClubReadIdentity
    let token: String?
    public init(identity: ClubReadIdentity, token: String?) throws {
        guard identity.accountID == nil || (identity.accountID! > 0 && token.map(AuthRequestBuilder.isValidToken) == true) else { throw ClubCommunityFailure.invalid }
        self.identity = identity; self.token = token
    }
}
public enum ClubCommunityRead: Equatable {
    case posts(clubID: Int, page: Int), feed(page: Int), comments(postID: Int, page: Int), history(postID: Int)
    var suffix: String { switch self { case .posts: return "list"; case .feed: return "feed"; case .comments: return "comment/list"; case .history: return "history" } }
    var fields: [String: Any] {
        switch self {
        case let .posts(id, page): return ["clubId": id, "pageNum": page, "pageSize": 20]
        case let .feed(page): return ["pageNum": page, "pageSize": 20]
        case let .comments(id, page): return ["postId": id, "pageNum": page, "pageSize": 50]
        case let .history(id): return ["id": id]
        }
    }
}
public struct ClubCommunitySnapshot {
    public let posts: [ClubCommunityPost], comments: [ClubCommunityComment], history: [ClubCommunityRevision]
    public let clubCount: Int?
}
public enum ClubCommunityOperation: Equatable {
    case create(content: String, images: [String])
    case update(content: String, images: [String], requestID: String)
    case pin(Bool, requestID: String), delete, report, toggleLike
    case comment(String), deleteComment, reportComment
    public var labelKey: String {
        switch self { case .create: return "create"; case .update: return "edit"; case .pin: return "pin"; case .delete: return "delete"; case .report: return "report"; case .toggleLike: return "like"; case .comment: return "comment"; case .deleteComment: return "deleteComment"; case .reportComment: return "reportComment" }
    }
    var suffix: String {
        switch self { case .create: return "create"; case .update: return "update"; case .pin: return "pin"; case .delete: return "delete"; case .report: return "report"; case .toggleLike: return "like"; case .comment: return "comment/create"; case .deleteComment: return "comment/delete"; case .reportComment: return "comment/report" }
    }
}
/// Must come from a fresh host membership read plus exact post/comment read under this epoch.
public struct ClubCommunityEvidence: Equatable {
    public let identity: ClubReadIdentity, clubID: Int, joined: Bool, owner: Bool, administrator: Bool
    public let post: ClubCommunityPost?, comment: ClubCommunityComment?
    public let observedAt: Date
    public init(identity: ClubReadIdentity, clubID: Int, joined: Bool, owner: Bool, administrator: Bool, post: ClubCommunityPost? = nil, comment: ClubCommunityComment? = nil, observedAt: Date = Date()) {
        self.identity = identity; self.clubID = clubID; self.joined = joined; self.owner = owner; self.administrator = administrator; self.post = post; self.comment = comment; self.observedAt = observedAt
    }
    public func allows(_ operation: ClubCommunityOperation) -> Bool {
        guard let viewer = identity.accountID, viewer > 0, clubID > 0 else { return false }
        if let post, post.clubID != clubID { return false }
        if let comment, comment.postID != post?.id { return false }
        let mine = post?.authorMemberID == viewer
        let manager = owner || administrator || post?.viewerCanManage == true
        switch operation {
        case .create: return joined || owner
        case .update: return post != nil && (post?.type == 2 ? manager : mine)
        case .pin: return post?.type == 2 && manager
        case .delete: return post != nil && mine
        case .report: return post != nil && !mine
        case .toggleLike, .comment: return post != nil
        case .deleteComment: return comment != nil && (comment?.memberID == viewer || manager)
        case .reportComment: return comment != nil && !(comment?.memberID == viewer || manager)
        }
    }
}
public struct ClubCommunityReview: Equatable, Identifiable {
    public let id: UUID, operation: ClubCommunityOperation, evidence: ClubCommunityEvidence
    public init(operation: ClubCommunityOperation, evidence: ClubCommunityEvidence) throws {
        guard evidence.allows(operation) else { throw ClubCommunityFailure.forbidden }
        id = UUID(); self.operation = operation; self.evidence = evidence
        _ = try fields()
    }
    public var lockKey: String { "\(evidence.identity.accountID ?? 0):\(evidence.clubID):\(evidence.post?.id ?? 0):\(evidence.comment?.id ?? 0)" }
    func fields() throws -> [String: Any] {
        func body(_ content: String, _ images: [String]) throws {
            guard content.count <= 300, images.count <= 9, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty,
                  images.allSatisfy({ !$0.isEmpty && !$0.contains(";") }) else { throw ClubCommunityFailure.invalid }
        }
        let postID = evidence.post?.id ?? 0, commentID = evidence.comment?.id ?? 0
        switch operation {
        case let .create(content, images):
            try body(content, images); var fields: [String: Any] = ["clubId": evidence.clubID, "content": content]
            if !images.isEmpty { fields["images"] = images.joined(separator: ";") }; return fields
        case let .update(content, images, key):
            try body(content, images); guard !key.isEmpty else { throw ClubCommunityFailure.invalid }
            return ["id": postID, "content": content, "images": images.joined(separator: ";"), "version": evidence.post!.version, "requestId": key]
        case let .pin(pinned, key):
            guard !key.isEmpty else { throw ClubCommunityFailure.invalid }
            return ["id": postID, "pinned": pinned, "version": evidence.post!.version, "requestId": key]
        case .delete, .report: return ["id": postID]
        case .toggleLike: return ["postId": postID]
        case let .comment(content):
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ClubCommunityFailure.invalid }
            return ["postId": postID, "content": content]
        case .deleteComment, .reportComment: return ["id": commentID]
        }
    }
}
