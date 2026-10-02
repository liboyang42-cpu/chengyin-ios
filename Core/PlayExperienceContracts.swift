import Foundation

/// JSON scalar fidelity for source-backed payloads. Never log these values: answers and
/// evidence can be private. Numeric strings are tolerated only by explicit accessors.
public indirect enum PlayWireValue: Codable, Equatable {
    case object([String: PlayWireValue]), array([PlayWireValue]), string(String), integer(Int64), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self), v.isFinite { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: Self].self) { self = .object(v) }
        else { self = .array(try c.decode([Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): guard v.isFinite else { throw APIError.invalidRequest }; try c.encode(v)
        case .bool(let v): try c.encode(v)
        }
    }
    public subscript(_ key: String) -> Self { object?[key] ?? .null }
    public var object: [String: Self]? { if case .object(let v) = self { return v }; return nil }
    public var array: [Self]? { if case .array(let v) = self { return v }; return nil }
    public var text: String? { if case .string(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var integer: Int? {
        if case .integer(let v) = self, abs(Double(v)) <= 9_007_199_254_740_991 { return Int(exactly: v) }
        return nil
    }
    public var tolerantInteger: Int? { integer ?? text.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    public var double: Double? {
        switch self { case .integer(let v): return Double(v); case .number(let v): return v; default: return nil }
    }
    static func int(_ v: Int) -> Self { .integer(Int64(v)) }
    func decoded<T: Decodable>(_ type: T.Type = T.self) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
}

public struct PlayExperienceSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    /// Supplied from RegionalSessionStorageScope.service, never from UI language.
    public let namespace: String
    let token: String
    public init(accountID: Int, epoch: UInt64, namespace: String, token: String) throws {
        guard accountID > 0, !namespace.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.namespace = namespace; self.token = token
    }
}
public struct PlayRouteAdvance: Equatable {
    public let actionID: String
    public let expectedVersion: Int
    public init(actionID: String, expectedVersion: Int) throws {
        let id = actionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= 96, expectedVersion >= 0 else { throw APIError.invalidRequest }
        self.actionID = id; self.expectedVersion = expectedVersion
    }
    var fields: [String: String] { ["routeActionId": actionID, "expectedRouteVersion": String(expectedVersion)] }
}
public enum PlayExperienceError: Error, Equatable {
    case disabled, staleSession, busy, invalidAction, unknownResult, unsupported, malformed
    case rejected(Int, String?), unauthorized
}
public struct PlayExperienceDocument: Decodable, Equatable {
    public let base: PlayNodesResult
    public let extras: [Int: PlayNodeExtras]
    public let chapterStories: [Int: ChapterStoryDocument]
    public let storyVariables: [String: PlayWireValue]
    public let storyVoices: [String: PlayWireValue]
    public let storyThoughts: [PlayWireValue]
    public init(from decoder: Decoder) throws {
        base = try PlayNodesResult(from: decoder)
        let raw = try PlayWireValue(from: decoder)
        var rows: [Int: PlayNodeExtras] = [:]
        for row in raw["nodes"].array ?? [] {
            guard let id = row["nodeId"].tolerantInteger, id > 0 else { throw APIError.malformedResponse }
            rows[id] = PlayNodeExtras(raw: row)
        }
        extras = rows
        var chapters: [Int: ChapterStoryDocument] = [:]
        for rawChapter in raw["chapters"].array ?? [] {
            let chapter = try ChapterStoryDocument(raw: rawChapter)
            guard chapters[chapter.chapterID] == nil else { throw APIError.malformedResponse }
            chapters[chapter.chapterID] = chapter
        }
        chapterStories = chapters
        storyVariables = raw["vars"].object ?? [:]
        storyVoices = raw["storyVoices"].object ?? [:]
        storyThoughts = raw["routeState"]["thoughts"].array ?? []
    }
}
public struct PlayNodeExtras: Equatable {
    public let merchantID: Int?
    public let hint1: String?
    public let hint2: String?
    public let hintCost: Int?
    public let hintLocked: Bool?
    public let hintCount: Int?
    public let puzzleScoring: Bool?
    public let puzzleHintLevel: Int?
    public let puzzleScoreCap: Int?
    public let usedHints: [String]
    public let sensorConfig: PlayWireValue
    public let uploadedImage: String?
    public let storyImage: String?
    public let audioURL: String?
    public let medalName: String?
    public let medalImage: String?
    public let couponID: Int?
    init(raw: PlayWireValue) {
        merchantID = raw["merchantId"].tolerantInteger
        hint1 = raw["hint1"].text; hint2 = raw["hint2"].text; hintCost = raw["hintCost"].tolerantInteger
        hintLocked = raw["hintLocked"].bool; hintCount = raw["hintCount"].tolerantInteger
        puzzleScoring = raw["puzzleScoring"].bool; puzzleHintLevel = raw["puzzleHintLevel"].tolerantInteger
        puzzleScoreCap = raw["puzzleScoreCap"].tolerantInteger
        usedHints = raw["usedHints"].array?.compactMap(\.text) ?? []
        sensorConfig = raw["sensorConfig"]; uploadedImage = raw["imgUrl"].text; storyImage = raw["storyImg"].text; audioURL = raw["audioUrl"].text
        medalName = raw["medalName"].text; medalImage = raw["medalImg"].text; couponID = raw["couponId"].tolerantInteger
    }
}
public enum PlayNodeTask: String, CaseIterable {
    case answer, photo, scan, arrive, preference, sensor, merchantScan, merchantPhoto, merchantVerify, unsupported
    public static func resolve(mode: Int?, node: PlayNode) -> Self {
        if mode == 2 {
            if node.arrived != true { return .merchantScan }
            if node.selfReported != true { return .merchantPhoto }
            return .merchantVerify
        }
        guard mode == 1 else { return .unsupported }
        switch node.validationMethod {
        case 0, 5: return .arrive
        case 1, 3: return .answer
        case 2: return .photo
        case 4: return .scan
        case 6: return .preference
        case 7: return .sensor
        case nil:
            if node.needAnswer == true { return .answer }
            if node.needScan == true { return .scan }
            return .arrive
        default: return .unsupported
        }
    }
}
public struct PlayHintReceipt: Equatable {
    public let hints: [String]
    public let cost: Int?
    public let level: Int?
    public let hintCount: Int?
    public let scoreCap: Int?
    init(_ raw: PlayWireValue) throws {
        guard raw.object != nil else { throw PlayExperienceError.malformed }
        let hints = raw["hints"].array?.compactMap(\.text) ?? [raw["hint1"].text, raw["hint2"].text, raw["hint"].text].compactMap { $0 }
        self.hints = hints.filter { !$0.isEmpty }; cost = raw["cost"].tolerantInteger
        level = raw["level"].tolerantInteger; hintCount = raw["hintCount"].tolerantInteger; scoreCap = raw["scoreCap"].tolerantInteger
        guard !self.hints.isEmpty, [cost, level, hintCount, scoreCap].compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else { throw PlayExperienceError.malformed }
    }
}
public struct PlayEndingDocument: Decodable, Equatable {
    public struct Fragment: Decodable, Equatable, Identifiable {
        public let step: Int; public let name: String; public let nodeId: Int?; public let text: String?
        public var id: Int { step }
    }
    public let opener: String
    public let fragments: [Fragment]
    public var hasStory: Bool { !fragments.isEmpty }
}
public struct PlayCompanionLeaderboard: Equatable {
    public struct Row: Equatable, Identifiable {
        public let id: Int; public let rank: Int?; public let name: String?; public let score: Int; public let rankPercentage: String?
        init(_ raw: PlayWireValue) throws {
            guard let id = raw["memberId"].integer, id > 0, let score = raw["score"].integer, score >= 0 else { throw PlayExperienceError.malformed }
            self.id = id; self.score = score; rank = raw["rank"].integer; name = raw["nickname"].text; rankPercentage = raw["rankPercentage"].text
            guard raw["rank"] == .null || (rank ?? 0) > 0 else { throw PlayExperienceError.malformed }
        }
    }
    public let entries: [Row]
    public let me: Row
    init(_ raw: PlayWireValue) throws {
        guard let list = raw["list"].array, list.count <= 50 else { throw PlayExperienceError.malformed }
        entries = try list.map(Row.init); me = try Row(raw["me"])
        guard Set(entries.map(\.id)).count == entries.count,
              entries.enumerated().allSatisfy({ $0.element.rank == $0.offset + 1 }) else { throw PlayExperienceError.malformed }
        if let ranked = entries.first(where: { $0.id == me.id }) {
            guard ranked.rank == me.rank, ranked.score == me.score else { throw PlayExperienceError.malformed }
        } else if me.rank != nil { throw PlayExperienceError.malformed }
    }
}
public struct PlayLeadProgress: Equatable {
    public struct Member: Equatable, Identifiable {
        public let id: Int; public let name: String?; public let done: Int?; public let arrived: Bool; public let isLeader: Bool
    }
    public let exists: Bool
    public let isLeader: Bool
    public let leaderMemberID: Int?
    public let status: Int?
    public let chapterName: String?
    public let broadcast: String?
    public let arrived: Int?
    public let meArrived: Bool
    public let members: [Member]
    public var allArrived: Bool { !members.isEmpty && (arrived ?? -1) >= members.count }
    init(_ raw: PlayWireValue) throws {
        guard let exists = raw["exists"].bool else { throw PlayExperienceError.malformed }
        self.exists = exists; isLeader = raw["isLeader"].bool == true; leaderMemberID = raw["leaderMemberId"].integer
        status = raw["status"].integer; chapterName = raw["chapterName"].text; broadcast = raw["broadcast"].text
        arrived = raw["arrived"].integer; meArrived = raw["meArrived"].bool == true || raw["meArrived"].integer == 1
        members = try (raw["members"].array ?? []).map { item in
            guard let id = item["memberId"].integer, id > 0 else { throw PlayExperienceError.malformed }
            return Member(id: id, name: item["nickname"].text, done: item["done"].integer, arrived: item["arrived"].bool == true, isLeader: item["isLeader"].bool == true)
        }
        guard Set(members.map(\.id)).count == members.count else { throw PlayExperienceError.malformed }
    }
    public func allows(_ action: PlayLeadAction, accountID: Int) -> Bool {
        if action == .arrive { return exists && !meArrived }
        guard isLeader, leaderMemberID == accountID else { return false }
        if action == .start { return !exists }
        guard exists else { return false }
        return action != .unlockChapter || allArrived
    }
}
public enum PlayLeadAction: String, CaseIterable {
    case start, arrive, broadcast, unlockChapter = "unlock-chapter", settle, editTime = "edit-ops"
}
