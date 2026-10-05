import Foundation

public enum SquareReportFailure: Error, Equatable {
    case disabled, signedOut, invalid, malformed, stale, busy, locked, unknown, rejected(Int)
}

/// Only the two source-backed Square subjects are accepted here. A Club post ID
/// must never be reinterpreted as a community content ID.
public struct SquareReportTarget: Equatable, Hashable {
    public let source: SocialActionTarget
    public var type: String { source.commentID == nil ? "CONTENT" : "COMMENT" }
    public var id: Int { source.commentID ?? source.postID ?? 0 }
    public let version: Int
    public let postVersion: Int
    public init(post: SquarePost, comment: SquareComment? = nil) throws {
        guard post.generation == .communityV1, post.id > 0, let postVersion = post.version, postVersion >= 0 else { throw SquareReportFailure.invalid }
        self.postVersion = postVersion
        if let comment {
            guard comment.generation == .communityV1, comment.communityPostID == post.id,
                  let version = comment.version, version >= 0 else { throw SquareReportFailure.invalid }
            source = .comment(postID: post.id, commentID: comment.id); self.version = version
        } else { source = .post(post.id); version = postVersion }
    }

    var lockKey: String { "versioned-report:\(type):\(id)" }
}

public struct SquareReportReason: Equatable, Identifiable {
    public let id: String
    public let label: String
    public let emergency: Bool
    public let priority: String
    public let firstResponseMinutes: Int
    init(_ raw: SquareGovernanceJSON) throws {
        guard let code = raw["code"].string, !code.isEmpty, code.utf8.count <= 64,
              code.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 95 }),
              let label = raw["label"].string, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let emergency = raw["emergency"].bool, let priority = raw["priority"].string, !priority.isEmpty,
              let minutes = raw["firstResponseMinutes"].int, minutes > 0 else { throw SquareReportFailure.malformed }
        id = code; self.label = label; self.emergency = emergency; self.priority = priority; firstResponseMinutes = minutes
    }
}

public struct SquareReportPolicy: Equatable {
    public let version: String
    public let reasons: [SquareReportReason]
    public let targetTypes: [String]
    public let anonymityPolicy: String
    public let emergencyGuidanceCode: String?
    public init(raw: SquareGovernanceJSON) throws {
        guard let version = raw["policyVersion"].string, !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rows = raw["reasons"].array, !rows.isEmpty, rows.count <= 100,
              let types = raw["targetTypes"].array, types.allSatisfy({ $0.string != nil }),
              let codes = raw["reasonCodes"].array, codes.allSatisfy({ $0.string != nil }),
              let anonymity = raw["anonymityPolicy"].string, !anonymity.isEmpty else { throw SquareReportFailure.malformed }
        let parsed = try rows.map(SquareReportReason.init)
        guard Set(parsed.map(\.id)).count == parsed.count, Set(parsed.map(\.label)).count == parsed.count,
              codes.compactMap(\.string) == parsed.map(\.id),
              Set(types.compactMap(\.string)).count == types.count else { throw SquareReportFailure.malformed }
        self.version = version; reasons = parsed; targetTypes = types.compactMap(\.string)
        anonymityPolicy = anonymity; emergencyGuidanceCode = raw["emergencyGuidanceCode"].string
    }
}

public struct SquareReportSnapshot: Equatable {
    public let identity: SquareGovernanceIdentity
    public let target: SquareReportTarget
    public let policy: SquareReportPolicy
    public let subject: SocialActionSnapshot
    public let observedAt: Date
    public init(identity: SquareGovernanceIdentity, target: SquareReportTarget, policy: SquareReportPolicy,
                subject: SocialActionSnapshot, observedAt: Date = Date()) throws {
        guard identity.valid, target.source == subject.target, policy.targetTypes.contains(target.type) else { throw SquareReportFailure.invalid }
        try subject.validate()
        guard subject.post?.generation == .communityV1, (subject.post?.version ?? -1) >= 0 else { throw SquareReportFailure.invalid }
        if let comment = subject.comment {
            guard comment.generation == .communityV1, comment.communityPostID == target.source.postID, (comment.version ?? -1) >= 0 else { throw SquareReportFailure.invalid }
        }
        guard subject.post?.version == target.postVersion, (subject.comment?.version ?? subject.post?.version) == target.version else { throw SquareReportFailure.stale }
        if let comment = subject.comment, comment.memberID == identity.accountID { throw SquareReportFailure.invalid }
        self.identity = identity; self.target = target; self.policy = policy; self.subject = subject; self.observedAt = observedAt
    }
    func sameContext(as other: Self) -> Bool {
        identity == other.identity && target == other.target && policy == other.policy && subject.sameContext(as: other.subject)
    }
}

public struct SquareReportReview: Equatable, Identifiable {
    public let id = UUID()
    public let requestID: String
    public let snapshot: SquareReportSnapshot
    public let reason: SquareReportReason
    public let description: String
    public let createdAt: Date
    init(snapshot: SquareReportSnapshot, reasonCode: String, description: String, now: Date) throws {
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reason = snapshot.policy.reasons.first(where: { $0.id == reasonCode }),
              !description.isEmpty, description.utf16.count <= 2000 else { throw SquareReportFailure.invalid }
        self.snapshot = snapshot; self.reason = reason; self.description = description; createdAt = now
        requestID = "square-report-\(UUID().uuidString)"
    }
}

/// Keep only the reporter-visible fields. Never retain server payload hashes,
/// principal identifiers or internal moderation notes returned by a raw receipt.
public struct SquareReportReceipt: Equatable, Identifiable {
    public let id: Int
    public let targetType: String
    public let targetID: Int
    public let reasonCode: String
    public let policyVersion: String
    public let description: String
    public let stage: String
    public let publicStage: String?
    public let decisionSummary: String?
    public init(raw: SquareGovernanceJSON) throws {
        guard let id = raw["id"].int, id > 0,
              let type = raw["targetType"].string, ["CONTENT", "COMMENT"].contains(type),
              let targetID = raw["targetId"].int, targetID > 0,
              let reason = raw["reasonCode"].string, !reason.isEmpty,
              let version = raw["policyVersion"].string, !version.isEmpty,
              let description = raw["description"].string, !description.isEmpty,
              let stage = raw["stage"].string, !stage.isEmpty else { throw SquareReportFailure.malformed }
        self.id = id; targetType = type; self.targetID = targetID; reasonCode = reason
        policyVersion = version; self.description = description; self.stage = stage
        publicStage = raw["publicStage"].string; decisionSummary = raw["decisionSummary"].string
    }
    func matches(_ review: SquareReportReview) -> Bool {
        targetType == review.snapshot.target.type && targetID == review.snapshot.target.id &&
        reasonCode == review.reason.id && policyVersion == review.snapshot.policy.version && description == review.description
    }
}
