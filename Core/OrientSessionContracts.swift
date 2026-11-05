import Foundation

/// Source contract selection is separate from endpoint/deployment authorization.
/// The default freeze has no current lookup. The host may explicitly choose c6
/// only after verifying its test deployment and approving the additional routes.
public enum OrientSessionContract: Equatable {
    case frozen58, currentC6
}

public struct OrientSessionList: Decodable, Equatable {
    public let sessions: [OrientSessionView]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try c.decode([OrientSessionView].self, forKey: .sessions)
        guard Set(sessions.map(\.sessionID)).count == sessions.count else { throw APIError.malformedResponse }
    }
    private enum CodingKeys: String, CodingKey { case sessions }
}

/// Frozen source: hengyin 58f4cc4, ApiOrient{Session,Scoring,}Controller.
/// Orienteering is product_type=1. Activity play still requires the actual topic ID.
public struct OrientSessionScope: Codable, Equatable, Hashable {
    public let topicID: Int
    public let activityID: Int
    public init(topicID: Int, activityID: Int = 0, productType: Int) throws {
        guard productType == 1, topicID > 0, activityID >= 0 else { throw APIError.invalidRequest }
        self.topicID = topicID; self.activityID = activityID
    }
    private enum CodingKeys: String, CodingKey { case topicID, activityID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(topicID: c.decode(Int.self, forKey: .topicID),
                      activityID: c.decode(Int.self, forKey: .activityID), productType: 1)
    }
    var fields: [String: String] { ["topicId": String(topicID), "activityId": String(activityID)] }
    var ownerFields: [String: String] {
        ["ownerType": activityID == 0 ? "1" : "2", "ownerId": String(activityID == 0 ? topicID : activityID)]
    }
}

public enum OrientSessionPhase: String, Codable {
    case prepared = "PREPARED", running = "RUNNING", finished = "FINISHED"
    case abandoned = "ABANDONED", disqualified = "DISQUALIFIED"
    public var isTerminal: Bool { self == .finished || self == .abandoned || self == .disqualified }
}

public struct OrientSessionView: Decodable, Equatable {
    public let sessionID: Int
    public let scope: OrientSessionScope
    public let phase: OrientSessionPhase
    public let status: Int
    public let configVersion: Int
    public let ackConfigVersion: Int?
    public let startedAt: Int?
    public let elapsedMs: Int?
    public let serverNow: Int
    public let resumed: Bool?
    public let replayed: Bool?
    private enum CodingKeys: String, CodingKey {
        case sessionId, topicId, activityId, phase, status, configVersion, ackConfigVersion
        case startedAt, elapsedMs, serverNow, resumed, replayed
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.orientInt(.sessionId)
        scope = try .init(topicID: c.orientInt(.topicId), activityID: c.orientInt(.activityId), productType: 1)
        phase = try c.decode(OrientSessionPhase.self, forKey: .phase)
        status = try c.orientInt(.status); configVersion = try c.orientInt(.configVersion)
        ackConfigVersion = try c.orientOptionalInt(.ackConfigVersion)
        startedAt = try c.orientOptionalInt(.startedAt); elapsedMs = try c.orientOptionalInt(.elapsedMs)
        serverNow = try c.orientInt(.serverNow)
        resumed = try c.decodeIfPresent(Bool.self, forKey: .resumed)
        replayed = try c.decodeIfPresent(Bool.self, forKey: .replayed)
        let expectedStatus = phase == .finished ? 1 : phase == .abandoned ? 2 : phase == .disqualified ? 3 : 0
        let validStatus = status == expectedStatus || (phase == .disqualified && status == 2)
        guard sessionID > 0, validStatus, configVersion >= 0, serverNow >= 0,
              ackConfigVersion == nil || ackConfigVersion == configVersion,
              startedAt == nil || startedAt! >= 0, elapsedMs == nil || elapsedMs! >= 0,
              (startedAt == nil) == (elapsedMs == nil),
              phase != .running || startedAt != nil else { throw APIError.malformedResponse }
    }
}

public struct OrientSessionSafety: Decodable, Equatable {
    public struct Blocker: Decodable, Equatable { public let code: String; public let message: String }
    public let allowed: Bool
    public let blockers: [Blocker]
    public let night: Bool
    public let insuranceRequired: Bool
    public let sosAvailable: Bool
}

public struct OrientSessionTeam: Decodable, Equatable {
    public let teamID: Int
    public let title: String?
    public let maxMembers: Int?
    public let joinedCount: Int?
    public let leaderMemberID: Int?
    private enum CodingKeys: String, CodingKey { case teamId, title, maxMembers, joinedCount, leaderMemberId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teamID = try c.orientInt(.teamId); title = try c.decodeIfPresent(String.self, forKey: .title)
        maxMembers = try c.orientOptionalInt(.maxMembers); joinedCount = try c.orientOptionalInt(.joinedCount)
        leaderMemberID = try c.orientOptionalInt(.leaderMemberId)
        guard teamID > 0, maxMembers == nil || maxMembers! >= 0, joinedCount == nil || joinedCount! >= 0,
              leaderMemberID == nil || leaderMemberID! > 0 else { throw APIError.malformedResponse }
    }
}

public struct OrientSessionRank: Decodable, Equatable {
    public let rank: Int
    public let teamID: Int
    public let title: String?
    public let activeCount: Int
    public let teamDoneCount: Int
    public let totalTasks: Int
    public let mine: Bool
    private enum CodingKeys: String, CodingKey { case rank, teamId, title, activeCount, teamDoneCount, totalTasks, mine }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.orientInt(.rank); teamID = try c.orientInt(.teamId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        activeCount = try c.orientInt(.activeCount); teamDoneCount = try c.orientInt(.teamDoneCount)
        totalTasks = try c.orientInt(.totalTasks); mine = try c.decode(Bool.self, forKey: .mine)
        guard rank > 0, teamID > 0, activeCount >= 0, teamDoneCount >= 0,
              totalTasks >= teamDoneCount else { throw APIError.malformedResponse }
    }
}

/// Dates and extra fields are kept as server facts. No local score or reward calculation.
public struct OrientSessionScore: Decodable, Equatable {
    public let sessionID: Int
    public let scope: OrientSessionScope
    public let status: Int
    public let totalCenti: Int
    public let byDimension: [String: Int]
    public let timeline: [OrientSessionJSON]
    public let settlement: OrientSessionSettlement?
    public let appeals: [OrientSessionJSON]
    public let disputes: [OrientSessionJSON]
    private enum CodingKeys: String, CodingKey {
        case sessionId, topicId, activityId, status, totalCenti, byDimension, timeline, settlement, appeals, disputes
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.orientInt(.sessionId)
        scope = try .init(topicID: c.orientInt(.topicId), activityID: c.orientInt(.activityId), productType: 1)
        status = try c.orientInt(.status); totalCenti = try c.orientInt(.totalCenti)
        let dimensions = try c.decode([String: OrientSessionJSON].self, forKey: .byDimension)
        var exactDimensions: [String: Int] = [:]
        for (key, value) in dimensions {
            guard let exact = value.exactInteger else { throw APIError.malformedResponse }
            exactDimensions[key] = exact
        }
        byDimension = exactDimensions
        timeline = try c.decode([OrientSessionJSON].self, forKey: .timeline)
        settlement = try c.decodeIfPresent(OrientSessionSettlement.self, forKey: .settlement)
        appeals = try c.decode([OrientSessionJSON].self, forKey: .appeals)
        disputes = try c.decode([OrientSessionJSON].self, forKey: .disputes)
        guard sessionID > 0, (0...3).contains(status), settlement == nil || settlement?.sessionID == sessionID,
              ["TASK", "PUZZLE", "BONUS", "PENALTY", "ADJUSTMENT"].allSatisfy({ byDimension[$0] != nil })
        else { throw APIError.malformedResponse }
    }
}

public struct OrientSessionSettlement: Decodable, Equatable {
    public let state: String
    public let settlementID: Int
    public let sessionID: Int
    public let totalCenti: Int
    public let pointsAwarded: Int
    public let xpAwarded: Int
    public let idempotencyKey: String
    private enum CodingKeys: String, CodingKey {
        case state, settlementId, sessionId, totalCenti, pointsAwarded, xpAwarded, idempotencyKey
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(String.self, forKey: .state)
        settlementID = try c.orientInt(.settlementId); sessionID = try c.orientInt(.sessionId)
        totalCenti = try c.orientInt(.totalCenti); pointsAwarded = try c.orientInt(.pointsAwarded)
        xpAwarded = try c.orientInt(.xpAwarded); idempotencyKey = try c.decode(String.self, forKey: .idempotencyKey)
        guard state == "SETTLED", settlementID > 0, sessionID > 0, pointsAwarded >= 0, xpAwarded >= 0,
              !idempotencyKey.isEmpty else { throw APIError.malformedResponse }
    }
}

public enum OrientSessionAlternativeType: String, Codable { case scan = "SCAN", photo = "PHOTO", quiz = "QUIZ" }
public struct OrientSessionTaskState: Decodable, Equatable {
    public struct Alternative: Decodable, Equatable {
        public let alternativeTaskType: OrientSessionAlternativeType
        public let promptText: String?
    }
    public let taskID: Int
    public let completed: Bool
    public let photoPendingReview: Bool
    public let completedVia: String?
    public let alternatives: [Alternative]
    private enum CodingKeys: String, CodingKey { case taskId, completed, photoPendingReview, completedVia, alternatives }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try c.orientInt(.taskId); completed = try c.decode(Bool.self, forKey: .completed)
        photoPendingReview = try c.decode(Bool.self, forKey: .photoPendingReview)
        completedVia = try c.decodeIfPresent(String.self, forKey: .completedVia)
        alternatives = try c.decode([Alternative].self, forKey: .alternatives)
        guard taskID > 0 else { throw APIError.malformedResponse }
    }
}

public struct OrientSessionTaskReceipt: Decodable, Equatable {
    public let sessionID: Int
    public let taskID: Int
    public let alternativeTaskType: OrientSessionAlternativeType?
    public let receiptID: String
    public let completedAt: Int
    public let elapsedMs: Int
    public let phase: OrientSessionPhase
    private enum CodingKeys: String, CodingKey { case sessionId, taskId, alternativeTaskType, receiptId, completedAt, elapsedMs, phase }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.orientInt(.sessionId); taskID = try c.orientInt(.taskId)
        alternativeTaskType = try c.decodeIfPresent(OrientSessionAlternativeType.self, forKey: .alternativeTaskType)
        receiptID = try c.decode(String.self, forKey: .receiptId)
        completedAt = try c.orientInt(.completedAt); elapsedMs = try c.orientInt(.elapsedMs)
        phase = try c.decode(OrientSessionPhase.self, forKey: .phase)
        guard sessionID > 0, taskID > 0, receiptID == "orient:task:\(taskID)", completedAt >= 0, elapsedMs >= 0,
              phase == .running || phase == .finished else { throw APIError.malformedResponse }
    }
}

/// Explicit user evidence only. PHOTO uses a previously uploaded, owned media URL;
/// selecting an alternative never grants camera, upload or location permission.
public enum OrientSessionAlternativeEvidence: Codable, Equatable {
    case scan(code: String), photo(picURL: String), quiz(answer: String)
    public var type: OrientSessionAlternativeType {
        switch self { case .scan: return .scan; case .photo: return .photo; case .quiz: return .quiz }
    }
    var fields: [String: String] {
        switch self { case .scan(let v): return ["code": v]
        case .photo(let v): return ["picUrl": v]
        case .quiz(let v): return ["answer": v] }
    }
    func validate() throws {
        guard let value = fields.values.first, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= 16_384 else { throw APIError.invalidRequest }
    }
}

public struct OrientSessionAlternativeReceipt: Decodable, Equatable {
    public let attemptID: Int
    public let taskID: Int
    public let alternativeTaskType: OrientSessionAlternativeType
    public let outcome: String
    public let completed: Bool
    public let completedVia: String?
    public let replay: Bool
    private enum CodingKeys: String, CodingKey { case attemptId, taskId, alternativeTaskType, outcome, completed, completedVia, replay }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attemptID = try c.orientInt(.attemptId); taskID = try c.orientInt(.taskId)
        alternativeTaskType = try c.decode(OrientSessionAlternativeType.self, forKey: .alternativeTaskType)
        outcome = try c.decode(String.self, forKey: .outcome); completed = try c.decode(Bool.self, forKey: .completed)
        completedVia = try c.decodeIfPresent(String.self, forKey: .completedVia)
        replay = try c.decode(Bool.self, forKey: .replay)
        guard attemptID > 0, taskID > 0,
              ["PENDING_REVIEW", "COMPLETED", "REJECTED", "ALREADY_COMPLETED", "SUPERSEDED"].contains(outcome),
              completed == (completedVia != nil) else { throw APIError.malformedResponse }
    }
}

/// Raw extensible server data, with 64-bit integers decoded before floating values.
public indirect enum OrientSessionJSON: Codable, Equatable {
    case object([String: OrientSessionJSON]), array([OrientSessionJSON]), integer(Int), number(Double)
    case string(String), bool(Bool), null
    var exactInteger: Int? {
        switch self {
        case .integer(let value): return value
        case .string(let text): guard let value = Int(text), String(value) == text else { return nil }; return value
        default: return nil
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Int.self) { self = .integer(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([Self].self) { self = .array(a) }
        else if let o = try? c.decode([String: Self].self) { self = .object(o) }
        else { self = .number(try c.decode(Double.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

extension KeyedDecodingContainer {
    func orientInt(_ key: Key) throws -> Int {
        if let n = try? decode(Int.self, forKey: key) { return n }
        let s = try decode(String.self, forKey: key)
        guard let n = Int(s), String(n) == s else { throw APIError.malformedResponse }
        return n
    }
    func orientOptionalInt(_ key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try orientInt(key)
    }
}
