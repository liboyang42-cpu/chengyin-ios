import Foundation

public enum SquareContentGeneration: String, Hashable { case unknown, legacySquare, communityV1 }
public struct SquareContentRoute: Hashable {
    public let id: Int
    public let generation: SquareContentGeneration
    public init(id: Int, generation: SquareContentGeneration) { self.id = id; self.generation = generation }
    public var valid: Bool { id > 0 && generation != .unknown }
}

public enum SquareFeedMode: String, CaseIterable, Hashable {
    case latest = "LATEST", following = "FOLLOWING", nearby = "NEARBY"
    case topic = "TOPIC", community = "COMMUNITY", featured = "FEATURED"
    case trending = "TRENDING", forYou = "FOR_YOU"
    // Flutter's visible modes and login gates; never locally simulate a feed.
    public static let visible: [Self] = [.latest, .following, .nearby, .topic, .community, .featured]
    public var requiresAccount: Bool { self == .following || self == .topic || self == .community }
}
public struct SquareQuery: Equatable, Hashable {
    public var mode: SquareFeedMode
    public var keyword: String?
    public var authorID: Int?
    public var cityCode: String?
    public var topicCode: String?
    public var communityID: Int?
    public init(mode: SquareFeedMode = .latest, keyword: String? = nil, authorID: Int? = nil,
                cityCode: String? = nil, topicCode: String? = nil, communityID: Int? = nil) {
        self.mode = mode; self.keyword = keyword; self.authorID = authorID
        self.cityCode = cityCode; self.topicCode = topicCode; self.communityID = communityID
    }
}
public struct SquareCursor: Equatable, Hashable {
    public let id: Int
    public let score: Int?
    public init(id: Int, score: Int? = nil) { self.id = id; self.score = score }
}
public struct SquareFeedPage: Equatable {
    public let items: [SquarePost]
    public let hasMore: Bool
    public let nextCursor: SquareCursor?
    public init(items: [SquarePost], hasMore: Bool, nextCursor: SquareCursor? = nil) {
        self.items = items; self.hasMore = hasMore; self.nextCursor = nextCursor
    }
}
public struct SquareCommentPage: Equatable {
    public let items: [SquareComment]
    public let pageNumber: Int
    public let pageSize: Int
    private let explicitContinuation: Bool?
    // Legacy uses raw page length. Versioned pagination counts root threads, so
    // replies must not manufacture a next page.
    public var hasMore: Bool { explicitContinuation ?? (items.count >= pageSize) }
    public init(items: [SquareComment], pageNumber: Int, pageSize: Int = 50, hasMore: Bool? = nil) {
        self.items = items; self.pageNumber = pageNumber; self.pageSize = pageSize; explicitContinuation = hasMore
    }
}
public enum SquareReadFailure: Error, Equatable {
    case signInRequired, cityRequired, topicRequired, communityRequired, unavailable
    case server(code: Int, message: String?)
}

// Only source fields used by this read module are retained. Coordinates, moderation internals,
// credentials and mutation payloads are deliberately absent from the display model.
public struct SquarePost: Decodable, Equatable, Identifiable {
    public private(set) var generation: SquareContentGeneration = .unknown
    public let version: Int?
    public func qualified(as generation: SquareContentGeneration) -> Self { var value = self; value.generation = generation; return value }
    public let id: Int
    public let memberID: Int
    public let contents: String?
    public let images: [String]
    public let address: String?
    public let cityCode: String?
    public let likeCount: Int
    public let dislikeCount: Int
    public let commentCount: Int
    public let isLiked: Int
    public let nickname: String?
    public let avatar: String?
    public let verified: Bool
    public let memberLevel: Int
    public let authorBadge: String?
    public let noticeBadge: String?
    public let clubID: Int?
    public let clubName: String?
    public let routeImage: String?
    public let referenceTitle: String?
    public let referenceCover: String?
    public let referenceType: String?
    public let referenceID: Int?
    public let dataID: Int?
    public let dataType: Int
    public let topicID: Int?
    public let isTopicTemplate: Bool
    public let nodeTotal: Int
    public let nodeDoneCount: Int
    public let completed: Bool
    public let createTime: String
    public let lifecycle: String
    public let audience: String
    public let disclosureType: String
    public let safetyLabels: [String]
    public let commentPolicy: String
    public let viewerCanComment: Bool
    public init(from decoder: Decoder) throws {
        let root = try SquareValue(from: decoder)
        guard root.object != nil else { throw APIError.malformedResponse }
        let post = root["post"].object == nil ? root : root["post"]
        version = post["version"].number
        id = post["id"].number ?? 0
        guard id > 0 else { throw APIError.malformedResponse }
        memberID = post.first("authorId", "memberId").number ?? 0
        contents = post.first("body", "contents").string
        let media = root["media"].array ?? []
        let mediaImages = media.filter { ($0.first("media_type", "mediaType").string ?? "IMAGE") == "IMAGE" }
            .compactMap { $0.first("derived_object_key", "derivedObjectKey").nonempty }
        images = mediaImages.isEmpty ? post["pics"].pictures : mediaImages
        address = post.first("poiName", "address").string
        cityCode = post.first("cityCode", "city_code").string
        likeCount = post.first("likeCount", "likeNum").number ?? 0
        dislikeCount = post["nolikeNum"].number ?? 0
        commentCount = post["commentCount"].number ?? 0
        isLiked = post["viewerLiked"].truthy ? 1 : (post["isLiked"].number ?? 0)
        nickname = post.first("authorNickname", "memberNickname").string
        avatar = post.first("authorAvatar", "memberAvatar").string
        verified = post["rz"].truthy
        memberLevel = post.first("memberLevelId", "member_level_id").integer ?? 0
        authorBadge = post.first("authorBadge", "author_badge").nonempty
        noticeBadge = post.first("noticeBadge", "notice_badge").nonempty
        clubID = post["clubId"].integer
        clubName = post["clubName"].nonempty
        let route = media.first { $0.first("media_type", "mediaType").string == "MAP_SNAPSHOT" }
        routeImage = route?.first("derived_object_key", "derivedObjectKey").string ?? root["routePreviewImg"].string
        let reference = root["references"].array?.first(where: { $0.object != nil }) ?? .null
        referenceType = reference.first("reference_type", "referenceType").nonempty
        referenceID = reference.first("reference_id", "referenceId").integer
        let rawSnapshot = reference.first("snapshot_json", "snapshotJson")
        let snapshot = rawSnapshot.object == nil ? rawSnapshot.parsedJSON : rawSnapshot
        referenceTitle = root["sportName"].string ?? snapshot.first("title", "name").nonempty
        referenceCover = root["sportCover"].string ?? snapshot.first("cover_url", "coverUrl").string
        let rawID = post.first("dataId", "data_id").integer ?? 0
        let rawType = post.first("dataType", "data_type").integer ?? 0
        let linkID = rawID > 0 ? rawID : (referenceID ?? 0)
        let linkType = rawType > 0 ? rawType : (["ACTIVITY": 1, "TOPIC": 2, "ROUTE": 3][referenceType ?? ""] ?? 0)
        dataID = linkID > 0 && linkType > 0 ? linkID : nil
        dataType = linkID > 0 && linkType > 0 ? linkType : 0
        topicID = root["sportTopicId"].integer ?? (referenceType == "TOPIC" ? referenceID : nil)
        isTopicTemplate = root["isTopicTemplate"].truthy
        nodeTotal = root["nodeTotal"].number ?? 0; nodeDoneCount = root["nodeDoneCount"].number ?? 0
        completed = root["completed"].truthy
        createTime = post.first("publishedAt", "createTime").text ?? ""
        lifecycle = post["lifecycle"].text ?? "PUBLISHED"
        audience = post["audience"].text ?? "PUBLIC"
        disclosureType = post["disclosureType"].text ?? "NONE"
        let labels = post.first("safetyLabelsJson", "safety_labels_json")
        safetyLabels = (labels.array ?? labels.parsedJSON.array ?? []).compactMap(\.nonempty)
        commentPolicy = post["commentPolicy"].text ?? "EVERYONE"
        viewerCanComment = root["viewerCanComment"].isNull || root["viewerCanComment"].truthy
    }
}
public struct SquareComment: Decodable, Equatable, Identifiable {
    public private(set) var generation: SquareContentGeneration = .unknown
    public let communityPostID: Int?
    public func qualified(as generation: SquareContentGeneration) -> Self { var value = self; value.generation = generation; return value }
    public let id: Int
    public let memberID: Int
    public let contents: String?
    public let images: [String]
    public let rating: Int
    public let likeCount: Int
    public let isLiked: Int
    public let nickname: String?
    public let avatar: String?
    public let createTime: String
    public let lifecycle: String
    public let approvalState: String
    /// Source numeric version, absent remains unknown; never default to zero for review.
    public let version: Int?
    public let rootID: Int?
    public let parentID: Int?
    public let repliedToMemberID: Int?
    public init(from decoder: Decoder) throws {
        let value = try SquareValue(from: decoder)
        communityPostID = value["post_id"].number
        id = value["id"].number ?? 0
        guard id > 0 else { throw APIError.malformedResponse }
        memberID = value.first("author_id", "authorId", "memberId").number ?? 0
        contents = value.first("body", "contents").string
        images = value["imgArr"].pictures
        rating = value["rating"].number ?? 0
        likeCount = value.first("like_count", "likeCount").number ?? 0
        isLiked = value.first("viewer_liked", "viewerLiked").truthy ? 1 : (value["isLiked"].number ?? 0)
        nickname = value.first("author_nickname", "authorNickname", "memberNickname").string
        avatar = value.first("author_avatar", "authorAvatar", "memberAvatar").string
        createTime = value.first("create_time", "createTime").text ?? ""
        lifecycle = value["lifecycle"].text ?? "PUBLISHED"
        approvalState = value.first("author_approval_state", "approvalState").text ?? "VISIBLE"
        version = value["version"].number
        rootID = value.first("root_id", "rootId").number
        parentID = value.first("parent_id", "parentId", "reply_id", "replyId").number
        repliedToMemberID = value.first("replied_to_member_id", "repliedToMemberId").number
    }
    public func replyName(in loaded: [Self]) -> String? {
        if let parentID, let name = loaded.first(where: { $0.id == parentID })?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        guard let repliedToMemberID else { return nil }
        return loaded.lazy.filter { $0.memberID == repliedToMemberID }.compactMap { $0.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
    public static func threaded(_ rows: [Self]) -> [Self] {
        let roots = rows.filter { $0.parentID == nil }.sorted { $0.id > $1.id }
        let rootIDs = Set(roots.map(\.id))
        var replies: [Int: [Self]] = [:], orphans: [Self] = []
        for row in rows where row.parentID != nil {
            if let root = row.rootID ?? row.parentID, rootIDs.contains(root) { replies[root, default: []].append(row) }
            else { orphans.append(row) }
        }
        return roots.flatMap { [$0] + (replies[$0.id] ?? []).sorted { $0.id < $1.id } } + orphans.sorted { $0.id > $1.id }
    }
}

// Private JSON value supports the source's limited aliases without storing arbitrary payloads.
indirect enum SquareValue: Decodable {
    case object([String: SquareValue]), array([SquareValue]), string(String), integer(Int), double(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: SquareValue].self) { self = .object(v) }
        else { self = .array(try c.decode([SquareValue].self)) }
    }
    var object: [String: SquareValue]? { if case .object(let v) = self { return v }; return nil }
    var array: [SquareValue]? { if case .array(let v) = self { return v }; return nil }
    var string: String? { if case .string(let v) = self { return v }; return nil }
    var number: Int? {
        if case .integer(let v) = self { return v }
        if case .double(let v) = self, v.isFinite, v >= Double(Int.min), v < Double(Int.max) { return Int(v) }
        return nil
    }
    var integer: Int? { number ?? string.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    var text: String? {
        switch self { case .string(let v): return v; case .integer(let v): return String(v)
        case .double(let v): return String(v); case .bool(let v): return String(v); default: return nil }
    }
    var nonempty: String? { guard let v = text?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }; return v }
    var isNull: Bool { if case .null = self { return true }; return false }
    var truthy: Bool { if case .bool(true) = self { return true }; return number == 1 || string == "1" }
    subscript(_ key: String) -> Self { object?[key] ?? .null }
    func first(_ keys: String...) -> Self { keys.lazy.map { self[$0] }.first { !$0.isNull } ?? .null }
    var parsedJSON: Self { guard let string else { return .null }; return (try? JSONDecoder().decode(Self.self, from: Data(string.utf8))) ?? .null }
    var pictures: [String] {
        if let array { return array.compactMap(\.nonempty) }
        guard let value = nonempty else { return [] }
        if value.hasPrefix("["), let array = parsedJSON.array { return array.compactMap(\.nonempty) }
        return value.components(separatedBy: CharacterSet(charactersIn: ";,，；")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
