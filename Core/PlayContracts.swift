import Foundation

/// Source: play_api.dart `_exactSession`. Never send both IDs or substitute a topic ID
/// for an activity ID. Public cases are validated before any transport operation.
public enum PlaySessionScope: Hashable {
    case activity(Int), topic(Int)
    public var id: Int { switch self { case .activity(let id), .topic(let id): return id } }
    public var isValid: Bool { id > 0 }
    public var fields: [String: String] {
        switch self { case .activity(let id): return ["activityId": String(id)]
        case .topic(let id): return ["topicId": String(id)] }
    }
}

/// Optional facts stay optional: missing completion, arrival, XP or duration is not zero.
/// Strings are plain server text, never Markdown/HTML, instructions or navigation.
public struct PlayNode: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let address: String?
    public let sortID: Int?
    public let done: Bool?
    public let arrived: Bool?
    public let selfReported: Bool?
    public let locked: Bool?
    public let validationMethod: Int?
    public let needScan: Bool?
    public let needAnswer: Bool?
    public let needGPS: Bool?
    public let question: String?
    public let questionImage: String?
    public let questionAudio: String?
    public let options: [String: String]?
    public let description: String?
    public let hookText: String?
    public let storyText: String?
    public let gameTitle: String?
    public let ruleInstructions: String?
    public let requiredMaterials: String?
    public let durationMinutes: Int?
    public let difficulty: String?
    public let players: String?
    public let photoRequirement: String?
    public let businessTime: String?
    public let openStatus: String?
    public let routeNodeState: String?
    public let lockReason: String?
    public let unlockAfterNodeID: Int?
    public let chapterID: Int?
    public let xp: Int?
    public let puzzleScore: Int?
    public let completionMode: String?
    public let sensorType: String?
    /// Retain unknown configuration rather than silently bypassing its prerequisite.
    public let advancedConfig: PlayJSONValue?

    private enum CodingKeys: String, CodingKey {
        case nodeId, name, address, sortId, done, arrived, selfReported, locked, validationMethod
        case needScan, needAnswer, needGps, question, questionImg, questionAudio, options, description
        case hookText, storyText, gameTitle, ruleInstructions, requiredMaterials, duration, difficulty
        case players, photoRequireDesc, businessTime, openStatus, routeNodeState, lockReason
        case unlockAfterNodeId, chapterId, xp, puzzleScore, completionMode, sensorType, advancedConfigJson
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let nodeID = try c.playInt(.nodeId), nodeID > 0 else { throw APIError.malformedResponse }
        id = nodeID
        name = try c.decodeIfPresent(String.self, forKey: .name)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        sortID = try c.playInt(.sortId)
        done = try c.playBool(.done); arrived = try c.playBool(.arrived)
        selfReported = try c.playBool(.selfReported); locked = try c.playBool(.locked)
        validationMethod = try c.playInt(.validationMethod)
        needScan = try c.playBool(.needScan); needAnswer = try c.playBool(.needAnswer); needGPS = try c.playBool(.needGps)
        question = try c.decodeIfPresent(String.self, forKey: .question)
        questionImage = try c.decodeIfPresent(String.self, forKey: .questionImg)
        questionAudio = try c.decodeIfPresent(String.self, forKey: .questionAudio)
        options = try c.decodeIfPresent([String: String].self, forKey: .options)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        hookText = try c.decodeIfPresent(String.self, forKey: .hookText)
        storyText = try c.decodeIfPresent(String.self, forKey: .storyText)
        gameTitle = try c.decodeIfPresent(String.self, forKey: .gameTitle)
        ruleInstructions = try c.decodeIfPresent(String.self, forKey: .ruleInstructions)
        requiredMaterials = try c.decodeIfPresent(String.self, forKey: .requiredMaterials)
        durationMinutes = try c.playInt(.duration)
        difficulty = try c.decodeIfPresent(String.self, forKey: .difficulty)
        players = try c.decodeIfPresent(String.self, forKey: .players)
        photoRequirement = try c.decodeIfPresent(String.self, forKey: .photoRequireDesc)
        businessTime = try c.decodeIfPresent(String.self, forKey: .businessTime)
        openStatus = try c.decodeIfPresent(String.self, forKey: .openStatus)
        routeNodeState = try c.decodeIfPresent(String.self, forKey: .routeNodeState)
        lockReason = try c.decodeIfPresent(String.self, forKey: .lockReason)
        unlockAfterNodeID = try c.playInt(.unlockAfterNodeId)
        chapterID = try c.playInt(.chapterId)
        xp = try c.playInt(.xp); puzzleScore = try c.playInt(.puzzleScore)
        completionMode = try c.decodeIfPresent(String.self, forKey: .completionMode)
        sensorType = try c.decodeIfPresent(String.self, forKey: .sensorType)
        advancedConfig = try c.decodeIfPresent(PlayJSONValue.self, forKey: .advancedConfigJson)
    }
    public var hasAdvancedPrerequisite: Bool {
        guard let advancedConfig else { return false }
        let value: PlayJSONValue
        if case .string(let encoded) = advancedConfig {
            guard let decoded = try? JSONDecoder().decode(PlayJSONValue.self, from: Data(encoded.utf8)) else { return true }
            value = decoded
        } else { value = advancedConfig }
        guard case .object(let fields) = value else { return true }
        // Recognized disabled sections do not prevent a basic task. Unknown sections do.
        let known: Set<String> = ["timer", "random", "branch", "leaderboard", "multiplayer"]
        for (key, section) in fields {
            guard known.contains(key), case .object(let config) = section,
                  case .bool(false)? = config["enabled"] else { return true }
        }
        return false
    }
}

public struct PlayChapter: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let description: String?
    private enum CodingKeys: String, CodingKey { case chapterId, name, description }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.playInt(.chapterId), id > 0 else { throw APIError.malformedResponse }
        self.id = id; name = try c.decodeIfPresent(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
    }
}

public struct PlayRouteState: Decodable, Equatable {
    public let mode: String?
    public let sessionID: Int?
    public let status: String?
    public let version: Int?
    public let currentNodeID: Int?
    public let recommendedNodeID: Int?
    public let nodeStates: [Int: String]
    public let lockReasons: [Int: String]
    public var isBranch: Bool { mode == "BRANCH_GRAPH" }
    private enum CodingKeys: String, CodingKey {
        case routeMode, sessionId, status, version, currentNodeId, recommendedNodeId, nodeStates, lockReasons
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .routeMode)
        sessionID = try c.playInt(.sessionId); status = try c.decodeIfPresent(String.self, forKey: .status)
        version = try c.playInt(.version); currentNodeID = try c.playInt(.currentNodeId)
        recommendedNodeID = try c.playInt(.recommendedNodeId)
        func map(_ key: CodingKeys) throws -> [Int: String] {
            let raw = try c.decodeIfPresent([String: String].self, forKey: key) ?? [:]
            var result: [Int: String] = [:]
            for (key, value) in raw {
                guard let id = Int(key), id > 0, result[id] == nil else { throw APIError.malformedResponse }
                result[id] = value
            }
            return result
        }
        nodeStates = try map(.nodeStates); lockReasons = try map(.lockReasons)
        guard version.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        if isBranch {
            guard (sessionID ?? 0) > 0, version != nil, status?.isEmpty == false,
                  !nodeStates.isEmpty else { throw APIError.malformedResponse }
        }
    }
}

public struct PlayNodesResult: Decodable, Equatable {
    public let topicID: Int?
    public let topicName: String?
    public let topicDescription: String?
    public let mode: Int?
    public let playable: Bool?
    public let registered: Bool?
    public let selfPlay: Bool?
    public let total: Int?
    public let doneCount: Int?
    public let timeNote: String?
    /// Kept verbatim. No server timezone contract: never infer expiry from local parsing.
    public let expiresAt: String?
    public let nodes: [PlayNode]
    public let chapters: [PlayChapter]
    public let routeState: PlayRouteState?
    private enum CodingKeys: String, CodingKey {
        case topicId, topicName, topicDesc, mode, playable, registered, selfPlay, total, doneCount
        case timeNote, expiresAt, nodes, chapters, routeState
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topicID = try c.playInt(.topicId); topicName = try c.decodeIfPresent(String.self, forKey: .topicName)
        topicDescription = try c.decodeIfPresent(String.self, forKey: .topicDesc)
        mode = try c.playInt(.mode); playable = try c.playBool(.playable)
        registered = try? c.decode(Bool.self, forKey: .registered); selfPlay = try c.playBool(.selfPlay)
        total = try c.playInt(.total); doneCount = try c.playInt(.doneCount)
        timeNote = try c.decodeIfPresent(String.self, forKey: .timeNote)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        // Required array: missing/null/non-object rows are errors, never an empty route.
        nodes = try c.decode([PlayNode].self, forKey: .nodes)
        chapters = try c.decodeIfPresent([PlayChapter].self, forKey: .chapters) ?? []
        routeState = try c.decodeIfPresent(PlayRouteState.self, forKey: .routeState)
        guard Set(nodes.map(\.id)).count == nodes.count, Set(chapters.map(\.id)).count == chapters.count,
              total.map({ $0 >= 0 }) ?? true, doneCount.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
    }
    public var allDone: Bool { if let total, let doneCount { return total > 0 && doneCount >= total }; return false }
}

public struct PlayAnswerReceipt: Decodable, Equatable {
    public let nodeID: Int
    public let firstTime: Bool?
    public let doneCount: Int?
    public let total: Int?
    public let completed: Bool?
    public let xp: Int?
    public let puzzleScore: Int?
    private enum CodingKeys: String, CodingKey { case nodeId, firstTime, done, total, completed, xp, score, puzzleScore }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.playInt(.nodeId), id > 0 else { throw APIError.malformedResponse }
        nodeID = id; firstTime = try c.playBool(.firstTime)
        doneCount = try c.playInt(.done); total = try c.playInt(.total); completed = try c.playBool(.completed)
        xp = try c.playInt(.xp) ?? c.playInt(.score); puzzleScore = try c.playInt(.puzzleScore)
    }
}

public indirect enum PlayJSONValue: Decodable, Equatable {
    case object([String: PlayJSONValue]), array([PlayJSONValue]), string(String), bool(Bool), number(Double), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String: PlayJSONValue].self) { self = .object(value) }
        else if let value = try? c.decode([PlayJSONValue].self) { self = .array(value) }
        else { self = .number(try c.decode(Double.self)) }
    }
}

extension KeyedDecodingContainer {
    func playInt(_ key: Key) throws -> Int? {
        if !contains(key) { return nil }
        if try decodeNil(forKey: key) { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let string = try? decode(String.self, forKey: key), let value = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
        throw APIError.malformedResponse
    }
    func playBool(_ key: Key) throws -> Bool? {
        if !contains(key) { return nil }
        if try decodeNil(forKey: key) { return nil }
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key), value == 0 || value == 1 { return value == 1 }
        if let value = try? decode(String.self, forKey: key) {
            if value == "true" || value == "1" { return true }
            if value == "false" || value == "0" { return false }
        }
        throw APIError.malformedResponse
    }
}
