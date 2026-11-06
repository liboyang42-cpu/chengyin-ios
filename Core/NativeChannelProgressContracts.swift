import Foundation

public enum NativeChannelProgressError: Error, Equatable {
    case invalid, malformed, closed, persistence, pendingCommand
    case server(status: Int, code: String?)
    public var staleCursor: Bool { if case .server(409, "BOARD_CURSOR_STALE") = self { return true }; return false }
}

public struct NativeChannelProgressIdentity: Codable, Equatable {
    public let actorID: Int64
    public let namespace: String
    public let origin: URL
    public let sessionEpoch: String
    public init(actorID: Int64, namespace: String, origin: URL, sessionEpoch: String) throws {
        guard actorID > 0, !namespace.isEmpty, !sessionEpoch.isEmpty else { throw NativeChannelProgressError.invalid }
        _ = try APIConfiguration(baseURL: origin)
        self.actorID = actorID; self.namespace = namespace; self.origin = origin; self.sessionEpoch = sessionEpoch
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.actorID == rhs.actorID && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8) &&
        lhs.origin.absoluteString.utf8.elementsEqual(rhs.origin.absoluteString.utf8) && lhs.sessionEpoch.utf8.elementsEqual(rhs.sessionEpoch.utf8)
    }
}

public struct NativeChannelProgressBoard: Decodable, Equatable, Identifiable {
    public var id: String { boardKey }
    public let boardKey: String
    public let title: String
    public let metric: String
    public let period: String
    public let scope: String
    public let subjectType: String
    public let teamRollup: String?
    public let rowLimit: Int
    public let visible: Bool
    public let revision: Int64
    public let topicId: Int64
    public let activityId: Int64
    public let filterSchemaJson: [String: String]
}

/// Optional facts are absent when the original producer reports UNCONFIRMED or no effort.
/// A null rank never becomes zero, and rows retain the server's order.
public struct NativeChannelProgressRow: Decodable, Equatable {
    public let subjectType: String?
    public let subjectId: Int64?
    public let topicId: Int64?
    public let activityId: Int64?
    public let playInstanceId: String?
    public let factSource: String?
    public let unit: String?
    public let required: Int?
    public let done: Int?
    public let completed: Bool?
    public let percent: Int?
    public let revision: String?
    public let asOf: String?
    public let displayName: String?
    public let metric: String?
    public let metricValue: Int64?
    public let rank: Int?
    public let rankKnown: Bool?
    public let state: String?
    public let reason: String?
    public let visible: Bool?
    public func validated() throws -> Self {
        if let state {
            guard ["UNCONFIRMED","NO_COMPLETED_EFFORT","NOT_APPLICABLE"].contains(state), rank == nil, rankKnown == false,
                  done == nil, required == nil, percent == nil, metricValue == nil else { throw NativeChannelProgressError.malformed }
        } else {
            guard ["MEMBER","TEAM"].contains(subjectType ?? ""), subjectId.map({ $0 > 0 }) == true,
                  required.map({ $0 > 0 }) == true, done.map({ $0 >= 0 }) == true, completed != nil,
                  percent.map({ (0...100).contains($0) }) == true, metric != nil, metricValue != nil,
                  revision?.isEmpty == false, rank.map({ $0 > 0 }) ?? true else { throw NativeChannelProgressError.malformed }
        }
        return self
    }
}

public struct NativeChannelProgressPage: Decodable, Equatable {
    public let visible: Bool
    public let revision: String
    public let asOf: String?
    public let boardKey: String?
    public let periodKey: String?
    public let list: [NativeChannelProgressRow]?
    public let me: NativeChannelProgressRow?
    public let nextCursor: String?
    public let hasMore: Bool?
    public func validated() throws -> Self {
        guard !revision.isEmpty else { throw NativeChannelProgressError.malformed }
        if visible {
            guard let list, list.count <= 50, let hasMore, hasMore == (nextCursor != nil),
                  list.allSatisfy({ ($0.rank == nil || $0.rank! > 0) && $0.state == nil }),
                  nextCursor?.isEmpty != true else { throw NativeChannelProgressError.malformed }
        } else if list != nil || nextCursor != nil || hasMore != nil { throw NativeChannelProgressError.malformed }
        for row in list ?? [] { _ = try row.validated() }
        if let me { _ = try me.validated() }
        return self
    }
}

public struct NativeChannelProgressVersion: Decodable, Equatable { public let visible: Bool; public let revision: String; public let asOf: String? }
public struct NativeChannelProgressDefinitions: Decodable { public let visible: Bool; public let list: [NativeChannelProgressBoard]? }
public struct NativeChannelProgressOverview: Decodable, Equatable {
    public struct Members: Decodable, Equatable { public let total: Int; public let totalCapped: Bool; public let completed: Int; public let avgPercent: Int? }
    public struct Team: Decodable, Equatable { public let teamId: Int64; public let rollup: String; public let required: Int; public let done: Int; public let completed: Bool }
    public let visible: Bool
    public let channelId: Int64?
    public let topicId: Int64?
    public let activityId: Int64?
    public let revision: String?
    public let asOf: String?
    public let members: Members?
    public let teams: [Team]?
}
public struct NativeChannelProgressMeter: Decodable, Equatable {
    public struct Visibility: Decodable, Equatable { public let aggregate: String; public let detail: String }
    public let visible: Bool
    public let subjectId: Int64?
    public let topicId: Int64?
    public let activityId: Int64?
    public let required: Int?
    public let done: Int?
    public let percent: Int?
    public let completed: Bool?
    public let asOf: String?
    public let revision: String?
    public let visibility: Visibility?
    public let currentNodeId: Int64?
    public let completedNodeIds: [Int64]?
}

public enum NativeChannelProgressScope: String, Codable, CaseIterable { case publicAccess = "PUBLIC", channel = "CHANNEL", team = "TEAM", onlyMe = "SELF" }
public enum NativeChannelProgressPhotoScope: String, Codable, CaseIterable { case onlyMe = "SELF", team = "TEAM", admin = "ADMIN" }
public enum NativeChannelProgressLeaderboardScope: String, Codable, CaseIterable { case included = "IN", out = "OUT" }
public struct NativeChannelProgressPrivacyValues: Codable, Equatable {
    public var aggregateScope: NativeChannelProgressScope
    public var detailScope: NativeChannelProgressScope
    public var photoScope: NativeChannelProgressPhotoScope
    public var leaderboardScope: NativeChannelProgressLeaderboardScope
    public init(aggregateScope: NativeChannelProgressScope, detailScope: NativeChannelProgressScope,
                photoScope: NativeChannelProgressPhotoScope, leaderboardScope: NativeChannelProgressLeaderboardScope) throws {
        guard detailScope != .publicAccess else { throw NativeChannelProgressError.invalid }
        self.aggregateScope = aggregateScope; self.detailScope = detailScope; self.photoScope = photoScope; self.leaderboardScope = leaderboardScope
    }
}
public struct NativeChannelProgressPrivacy: Decodable, Equatable {
    public struct Effective: Decodable, Equatable { public let aggregateScope: NativeChannelProgressScope; public let detailScope: NativeChannelProgressScope }
    public let aggregateScope: NativeChannelProgressScope
    public let detailScope: NativeChannelProgressScope
    public let photoScope: NativeChannelProgressPhotoScope
    public let leaderboardScope: NativeChannelProgressLeaderboardScope
    public let revision: Int64
    public let updatedAt: String?
    public let verifiedAt: String?
    public let effective: Effective?
    public let appliesTo: String
    public let requestId: String?
    public let status: String?
    public let replayed: Bool?
    public let outcomeKnown: Bool?
    public let outcomeConfirmed: Bool?
    public func values() throws -> NativeChannelProgressPrivacyValues {
        try .init(aggregateScope: aggregateScope, detailScope: detailScope, photoScope: photoScope, leaderboardScope: leaderboardScope)
    }
}
public struct NativeChannelProgressPrivacyCommand: Codable, Equatable {
    public let aggregateScope: NativeChannelProgressScope
    public let detailScope: NativeChannelProgressScope
    public let photoScope: NativeChannelProgressPhotoScope
    public let leaderboardScope: NativeChannelProgressLeaderboardScope
    public let expectedRevision: Int64?
    public let expectedUpdatedAt: String?
    public let requestId: String
    public init(values: NativeChannelProgressPrivacyValues, revision: Int64?, updatedAt: String?, requestID: String) throws {
        guard values.detailScope != .publicAccess, requestID.range(of: "^[A-Za-z0-9_-]{16,64}$", options: .regularExpression) != nil,
              (revision.map({ $0 >= 0 }) == true || (revision == nil && updatedAt?.isEmpty == false)) else { throw NativeChannelProgressError.invalid }
        aggregateScope = values.aggregateScope; detailScope = values.detailScope; photoScope = values.photoScope; leaderboardScope = values.leaderboardScope
        expectedRevision = revision; expectedUpdatedAt = updatedAt; requestId = requestID
    }
    public func matches(_ receipt: NativeChannelProgressPrivacy) -> Bool {
        receipt.requestId == requestId && receipt.status == "APPLIED" && receipt.appliesTo == "CHANNEL_PROGRESS" && receipt.outcomeKnown != false && receipt.outcomeConfirmed != false &&
        receipt.aggregateScope == aggregateScope && receipt.detailScope == detailScope && receipt.photoScope == photoScope && receipt.leaderboardScope == leaderboardScope &&
        (expectedRevision.map({ receipt.revision > $0 }) ?? (receipt.revision > 0)) && receipt.updatedAt?.isEmpty == false
    }
    public func wireBody() throws -> Data {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
public struct NativeChannelProgressQuery: Equatable {
    public let boardKey: String
    public let period: String
    public let completed: Bool?
    public let teamID: Int64?
    public let limit: Int
    public init(board: NativeChannelProgressBoard, period: String, completed: Bool? = nil, teamID: Int64? = nil, limit: Int = 30) throws {
        guard board.boardKey.range(of: "^[a-z][a-z0-9_]{0,31}$", options: .regularExpression) != nil,
              ["ALL","TOPIC","WEEK","MONTH"].contains(period), (1...50).contains(limit),
              completed == nil || board.filterSchemaJson["completed"] == "boolean",
              teamID == nil || (teamID! > 0 && board.filterSchemaJson["team_id"] == "int") else { throw NativeChannelProgressError.invalid }
        boardKey = board.boardKey; self.period = period; self.completed = completed; self.teamID = teamID; self.limit = limit
    }
}
