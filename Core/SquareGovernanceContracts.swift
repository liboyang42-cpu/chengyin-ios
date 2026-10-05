import Foundation

public enum SquareGovernanceFailure: Error, Equatable {
    case disabled, signedOut, forbidden, malformed, invalid, staleReview, busy, outcomeLocked, unknown, rejected(Int)
}
public enum SquareGovernanceJSON: Codable, Equatable {
    case object([String: SquareGovernanceJSON]), array([SquareGovernanceJSON]), string(String), integer(Int), decimal(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self) { self = .decimal(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try c.decode([Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .decimal(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> Self { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    public var int: Int? { if case .integer(let v) = self { return v }; return nil }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var array: [Self]? { if case .array(let v) = self { return v }; return nil }
}
public struct SquareGovernanceIdentity: Equatable, Hashable {
    public let accountID: Int
    public let epoch: UInt64
    public let namespace: String
    public init(accountID: Int, epoch: UInt64, namespace: String) { self.accountID = accountID; self.epoch = epoch; self.namespace = namespace }
    public var valid: Bool { accountID > 0 && !namespace.isEmpty }
}
public struct SquareEnforcement: Equatable, Identifiable {
    public let raw: SquareGovernanceJSON
    public var id: Int { raw["id"].int ?? 0 }
    public var type: String { raw["enforcement_type"].string ?? "UNKNOWN" }
    public var rule: String { raw["rule_code"].string ?? "" }
    public var status: String { raw["status"].string ?? "UNKNOWN" }
    public var appealStatus: String? { raw["appeal_status"].string }
    public var canRequestReview: Bool { id > 0 && raw["appeal_status"] == .null }
    public init(raw: SquareGovernanceJSON) throws { guard (raw["id"].int ?? 0) > 0 else { throw SquareGovernanceFailure.malformed }; self.raw = raw }
}
public struct SquareGovernanceNotification: Equatable, Identifiable {
    public let raw: SquareGovernanceJSON
    public var id: Int { raw["id"].int ?? 0 }
    public var postID: Int? { raw["post_id"].int }
    public var unread: Bool { raw["read_at"] == .null }
    public var payload: SquareGovernanceJSON {
        if let text = raw["payload_json"].string, let data = text.data(using: .utf8) { return (try? JSONDecoder().decode(SquareGovernanceJSON.self, from: data)) ?? .null }
        return raw["payload_json"]
    }
    public var action: String { payload["action"].string ?? "UNKNOWN" }
    public var publicNote: String? { action.hasPrefix("REPORT_STAGE_") ? payload["publicNote"].string : nil }
    public init(raw: SquareGovernanceJSON) throws { guard (raw["id"].int ?? 0) > 0 else { throw SquareGovernanceFailure.malformed }; self.raw = raw }
}
public enum SquarePreference: String, CaseIterable, Codable { case interactionEnabled, mentionEnabled, socialEnabled }
public struct SquareGovernanceComment: Equatable, Identifiable {
    public let generation: SquareContentGeneration
    public let id: Int
    public let postID: Int
    public let postAuthorID: Int
    public let commentAuthorID: Int
    public let version: Int?
    public let approvalState: String?
    public let lifecycle: String?
    public init(id: Int, postID: Int, postAuthorID: Int, raw: SquareGovernanceJSON, generation: SquareContentGeneration = .unknown) {
        self.generation = generation
        self.id = id; self.postID = postID; self.postAuthorID = postAuthorID
        commentAuthorID = raw["author_id"].int ?? raw["authorId"].int ?? raw["memberId"].int ?? 0
        version = raw["version"].int
        approvalState = raw["author_approval_state"].string ?? raw["approvalState"].string
        lifecycle = raw["lifecycle"].string
    }
    // Source: post author approves PENDING. A moderator role alone grants neither operation.
    public func canApprove(_ identity: SquareGovernanceIdentity) -> Bool { identity.valid && generation == .communityV1 && id > 0 && postID > 0 && identity.accountID == postAuthorID && approvalState == "PENDING" && (version ?? -1) >= 0 }
    public func canDelete(_ identity: SquareGovernanceIdentity) -> Bool { identity.valid && generation != .unknown && id > 0 && identity.accountID == commentAuthorID && (generation != .communityV1 || (version ?? -1) >= 0) }
}
public struct SquareGovernanceSnapshot: Equatable {
    public let identity: SquareGovernanceIdentity
    public let enforcementPages: Int
    public let notificationPages: Int
    public let enforcements: [SquareEnforcement]
    public let notifications: [SquareGovernanceNotification]
    public let preferences: SquareGovernanceJSON
    public let comments: [SquareGovernanceComment]
    public init(identity: SquareGovernanceIdentity, enforcements: [SquareEnforcement], notifications: [SquareGovernanceNotification], preferences: SquareGovernanceJSON, comments: [SquareGovernanceComment] = [], enforcementPages: Int = 1, notificationPages: Int = 1) {
        self.enforcementPages = enforcementPages; self.notificationPages = notificationPages
        self.identity = identity; self.enforcements = enforcements; self.notifications = notifications; self.preferences = preferences; self.comments = comments
    }
}
public enum SquareGovernanceAction: Equatable {
    case appeal(enforcementID: Int, reason: String)
    case markRead(notificationID: Int)
    case preferences([SquarePreference: Bool])
    case approveComment(postID: Int, commentID: Int)
    case deleteOwnComment(commentID: Int)
}
public struct SquareGovernanceReview: Equatable, Identifiable {
    public let id: UUID
    public let snapshot: SquareGovernanceSnapshot
    public let action: SquareGovernanceAction
    public let requestID: String
    public let createdAt: Date
    // Immutable review can only be constructed by validation in the coordinator.
    init(snapshot: SquareGovernanceSnapshot, action: SquareGovernanceAction, now: Date) {
        id = UUID(); self.snapshot = snapshot; self.action = action; createdAt = now
        requestID = "\(Self.prefix(action))-\(UUID().uuidString)"
    }
    static func prefix(_ action: SquareGovernanceAction) -> String {
        switch action { case .appeal: return "appeal"; case .markRead: return "notification-read"; case .approveComment: return "comment-approve"; default: return "review" }
    }
}
public enum SquareGovernanceReceipt: Equatable { case acknowledgedNeedsRefresh }
