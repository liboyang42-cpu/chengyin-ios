import Foundation

/// Viewer-relative API state. This is deliberately not the persistence status enum.
/// A blocked/unavailable peer is projected as none; the request APIs never disclose blocks.
public enum NativeFriendRelation: Int, Codable, Sendable {
    case none = 0, friend = 1, pendingOutgoing = 2, pendingIncoming = 3
}

public enum NativeFriendAction: String, Codable, Sendable {
    case request, accept, reject, cancel
}

/// Original F26/F27/F28/F29 provenance. Historical type name is retained for protected-journal compatibility; never permission.
public struct NativeFriendChannelSource: Codable, Equatable, Sendable {
    public let type: Int
    public let id: Int64
    public let generation: String?
    public var isValid: Bool { id > 0 && (type == 4 ? ["legacySquare", "communityV1"].contains(generation ?? "") : ([1, 2, 3].contains(type) && generation == nil)) }
    public init(channelID: Int64) throws { guard channelID > 0 else { throw NativeFriendFailure.invalid }; type = 1; id = channelID; generation = nil }
    public init(activityID: Int64) throws { guard activityID > 0 else { throw NativeFriendFailure.invalid }; type = 2; id = activityID; generation = nil }
    public init(teamID: Int64) throws { guard teamID > 0 else { throw NativeFriendFailure.invalid }; type = 3; id = teamID; generation = nil }
    public init(postID: Int64, generation: SquareContentGeneration) throws {
        guard postID > 0, generation == .legacySquare || generation == .communityV1 else { throw NativeFriendFailure.invalid }
        type = 4; id = postID; self.generation = generation.rawValue
    }
}

/// Stable identity of one explicit gesture, retained unchanged while its result is unknown.
public struct NativeFriendCommand: Codable, Equatable, Sendable {
    public let requestID: String
    public let peerID: Int64
    public let action: NativeFriendAction
    public let message: String
    public let expectedVersion: Int64?
    public let reviewID: Int64?
    public let source: NativeFriendChannelSource?

    public init(requestID: String = UUID().uuidString, peerID: Int64,
                action: NativeFriendAction, message: String = "", expectedVersion: Int64? = nil, reviewID: Int64? = nil, source: NativeFriendChannelSource? = nil) {
        self.requestID = requestID; self.peerID = peerID; self.action = action
        self.message = message; self.expectedVersion = expectedVersion; self.reviewID = reviewID; self.source = source
    }
}

/// A review belongs to one gesture and one exact server row, never a replacement row at the same index.
public struct NativeFriendActionReview: Equatable, Identifiable, Sendable {
    public var id: String { command.requestID }
    public let command: NativeFriendCommand
    public let item: NativeFriendItem?
    public let proposal: NativeFriendReview?
    public var message: String { item?.message ?? proposal?.message ?? command.message }
    public var displayName: String { item?.displayName ?? "" }
    public init(command: NativeFriendCommand, item: NativeFriendItem? = nil, proposal: NativeFriendReview? = nil) {
        self.command = command; self.item = item; self.proposal = proposal
    }
}

public struct NativeFriendRelationship: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let peerID: Int64
    public let state: NativeFriendRelation
    public let version: Int64
    public let conversationID: Int?
    enum CodingKeys: String, CodingKey {
        case viewerID = "viewer_id", peerID = "peer_id", state, version, conversationID = "conversation_id"
    }
}

public struct NativeFriendItem: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64 { peerID }
    public let peerID: Int64
    public let nickname: String
    public let state: NativeFriendRelation
    public let version: Int64
    public let message: String
    public let expiresAtMS: Int64
    public let friendRemark: String?
    public let groupID: Int64?
    public let starred: Int?
    public var displayName: String { friendRemark.flatMap { $0.isEmpty ? nil : $0 } ?? nickname }
    public init(peerID: Int64, nickname: String, state: NativeFriendRelation, version: Int64, message: String, expiresAtMS: Int64,
                friendRemark: String? = nil, groupID: Int64? = nil, starred: Int? = nil) {
        self.peerID = peerID; self.nickname = nickname; self.state = state; self.version = version; self.message = message
        self.expiresAtMS = expiresAtMS; self.friendRemark = friendRemark; self.groupID = groupID; self.starred = starred
    }
    enum CodingKeys: String, CodingKey {
        case peerID = "peer_id", nickname, state, version, message = "msg", expiresAtMS = "expires_at_ms"
        case friendRemark = "friend_remark", groupID = "group_id", starred
    }
}

public enum NativeFriendReviewState: String, Codable, Sendable {
    case pending = "PENDING_REVIEW", applied = "APPLIED", rejected = "REJECTED", cancelled = "CANCELLED", expired = "EXPIRED", invalidated = "INVALIDATED"
}
public struct NativeFriendReview: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let peerID: Int64
    public let requestID: String
    public let state: NativeFriendReviewState
    public let version: Int64
    public let message: String
    public let expiresAtMS: Int64
    enum CodingKeys: String, CodingKey {
        case id, peerID = "peer_id", requestID = "request_id", state, version, message = "msg", expiresAtMS = "expires_at_ms"
    }
}

public struct NativeFriendPage: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let incoming: [NativeFriendItem]
    public let outgoing: [NativeFriendItem]
    public let friends: [NativeFriendItem]
    public let hasMore: Bool
    public let nextCursor: Int64?
    public let reviews: [NativeFriendReview]?
    public let reviewHasMore: Bool?
    public let reviewNextCursor: Int64?
    public let groups: NativeFriendMetadataGroups?
    public init(viewerID: Int64, incoming: [NativeFriendItem], outgoing: [NativeFriendItem], friends: [NativeFriendItem], hasMore: Bool, nextCursor: Int64?, reviews: [NativeFriendReview]? = nil, reviewHasMore: Bool? = nil, reviewNextCursor: Int64? = nil, groups: NativeFriendMetadataGroups? = nil) {
        self.viewerID = viewerID; self.incoming = incoming; self.outgoing = outgoing; self.friends = friends; self.hasMore = hasMore; self.nextCursor = nextCursor
        self.reviews = reviews; self.reviewHasMore = reviewHasMore; self.reviewNextCursor = reviewNextCursor; self.groups = groups
    }
    enum CodingKeys: String, CodingKey {
        case viewerID = "viewer_id", incoming, outgoing, friends, hasMore = "has_more", nextCursor = "next_cursor"
        case reviews, groups, reviewHasMore = "review_has_more", reviewNextCursor = "review_next_cursor"
    }
}

public struct NativeFriendReceipt: Codable, Equatable, Sendable {
    public let viewerID: Int64
    public let peerID: Int64
    public let action: NativeFriendAction
    public let requestID: String
    public let outcome: String
    public let payloadHash: String?
    public let relationship: NativeFriendRelationship?
    public let review: NativeFriendReview?
    public init(viewerID: Int64, peerID: Int64, action: NativeFriendAction, requestID: String, outcome: String, relationship: NativeFriendRelationship?, review: NativeFriendReview? = nil, payloadHash: String? = nil) {
        self.viewerID = viewerID; self.peerID = peerID; self.action = action; self.requestID = requestID; self.outcome = outcome; self.relationship = relationship; self.review = review; self.payloadHash = payloadHash
    }
    enum CodingKeys: String, CodingKey {
        case viewerID = "viewer_id", peerID = "peer_id", action, requestID = "request_id", outcome, relationship, review, payloadHash = "payload_hash"
    }
}

public enum NativeFriendFailure: Error, Equatable {
    case unavailable, invalid, staleSession, notSent, unknown, rejected(Int)
}

@MainActor public protocol NativeFriendServing: AnyObject {
    var viewerID: Int64 { get }
    var canWrite: Bool { get }
    var isCurrent: Bool { get }
    func page(requests: Bool, cursor: Int64) async throws -> NativeFriendPage
    func reviewPage(cursor: Int64) async throws -> NativeFriendPage
    func relationship(peerID: Int64) async throws -> NativeFriendRelationship
    func write(_ command: NativeFriendCommand) async throws -> NativeFriendReceipt
    func receipt(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt
}

public extension NativeFriendServing {
    func reviewPage(cursor: Int64) async throws -> NativeFriendPage { try await page(requests: true, cursor: 0) }
}
