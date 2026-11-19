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

/// Free-exploration (mode 2) place visit check. Unknown values stay nil, never GPS by guess.
public enum PlayVisitCheck: String, Equatable { case gps = "GPS", scan = "SCAN", online = "ONLINE" }
/// Server visit time kept as sent: epoch milliseconds or verbatim text, no timezone guess.
public enum PlayVisitTime: Equatable {
    case epochMilliseconds(Int64), text(String)
    public var date: Date? { if case .epochMilliseconds(let value) = self { return Date(timeIntervalSince1970: Double(value) / 1000) }; return nil }
}

/// Optional facts stay optional: missing completion, arrival, XP or duration is not zero.
/// Strings are plain server text, never Markdown/HTML, instructions or navigation.
public struct PlayNode: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let npc: PlayNPCBrief?
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public let sortID: Int?
    public let done: Bool?
    public let arrived: Bool?
    public let selfReported: Bool?
    public let hasGame: Bool?
    public let gameDone: Bool?
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
    /// F07: a later city-route station not yet reached arrives with `imgUrl: null` and
    /// `imgHidden: true`. Any future station image shows a neutral silhouette instead.
    public let imgHidden: Bool?
    /// FE-STORY (mode 2 only). Missing or malformed values stay nil; see `PlaySnapshot.isStoryLocked`.
    public let visited: Bool?
    public let visitTime: PlayVisitTime?
    public let visitCheck: PlayVisitCheck?
    public let visitRadius: Int?
    public let storyLocked: Bool?
    /// FE-STORY 5.5: a teammate's visit unlocked this place for the whole ticket. Then
    /// `visited` is true and `visitTime` may be null. Missing or malformed stays nil.
    public let visitedByTeam: Bool?
    /// FE-STORY chapter text the server sends only after a visit (nil while locked).
    public let fragmentText: String?
    public let cardHookLong: String?
    /// CG-SH04-P1-3 (hengyin #866): a station behind an unsolved predecessor arrives with
    /// `address: null` and `addressHidden: true`. Malformed stays nil.
    public let addressHidden: Bool?
    /// FE-G5 (hengyin #866): this store's perk on `/api/play/nodes`, with its display terms.
    public let perk: PlayNodePerk?

    private enum CodingKeys: String, CodingKey {
        case nodeId, name, npc, address, latitude, longitude, sortId, done, arrived, selfReported, hasGame, gameDone, locked, validationMethod
        case needScan, needAnswer, needGps, question, questionImg, questionAudio, options, description
        case hookText, storyText, gameTitle, ruleInstructions, requiredMaterials, duration, difficulty
        case players, photoRequireDesc, businessTime, openStatus, routeNodeState, lockReason
        case unlockAfterNodeId, chapterId, xp, puzzleScore, completionMode, sensorType, advancedConfigJson
        case imgHidden, visited, visitTime, visitCheck, visitRadius, storyLocked, visitedByTeam, fragmentText, cardHookLong
        case addressHidden, perk
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let nodeID = try c.playInt(.nodeId), nodeID > 0 else { throw APIError.malformedResponse }
        id = nodeID
        // Malformed or unnamed NPC data offers no entrance; never infer from merchantId.
        npc = try? c.decode(PlayNPCBrief.self, forKey: .npc)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        latitude = c.playCoordinate(.latitude); longitude = c.playCoordinate(.longitude)
        sortID = try c.playInt(.sortId)
        done = try c.playBool(.done); arrived = try c.playBool(.arrived)
        selfReported = try c.playBool(.selfReported); locked = try c.playBool(.locked)
        hasGame = try c.playBool(.hasGame); gameDone = try c.playBool(.gameDone)
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
        // Additive fields never fail an otherwise valid read: malformed means unknown.
        imgHidden = try? c.playBool(.imgHidden)
        visited = try? c.playBool(.visited)
        storyLocked = try? c.playBool(.storyLocked)
        visitedByTeam = try? c.playBool(.visitedByTeam)
        fragmentText = try? c.decodeIfPresent(String.self, forKey: .fragmentText)
        cardHookLong = try? c.decodeIfPresent(String.self, forKey: .cardHookLong)
        addressHidden = try? c.playBool(.addressHidden)
        perk = try? c.decodeIfPresent(PlayNodePerk.self, forKey: .perk)
        visitRadius = (try? c.playInt(.visitRadius)).flatMap { $0 > 0 ? $0 : nil }
        visitCheck = (try? c.decodeIfPresent(String.self, forKey: .visitCheck)).flatMap { PlayVisitCheck(rawValue: $0.uppercased()) }
        if let millis = try? c.decodeIfPresent(Int64.self, forKey: .visitTime), millis > 0 { visitTime = .epochMilliseconds(millis) }
        else if let text = try? c.decodeIfPresent(String.self, forKey: .visitTime), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { visitTime = .text(text) }
        else { visitTime = nil }
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
    /// Narration from the same authorized /api/play/nodes response.
    public let audioURL: String?
    /// FE-STORY mode 2 only: every place in this chapter is still unvisited. Missing stays nil.
    public let chapterLocked: Bool?
    private enum CodingKeys: String, CodingKey { case chapterId, name, description, audioUrl, chapterLocked }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.playInt(.chapterId), id > 0 else { throw APIError.malformedResponse }
        self.id = id; name = try c.decodeIfPresent(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        audioURL = try c.decodeIfPresent(String.self, forKey: .audioUrl)
        chapterLocked = try? c.playBool(.chapterLocked)
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
    public let thoughts: [PlayWireValue]
    /// Nil covers absent, null, malformed or oversized optional history.
    public let decisionLog: PlayBranchHistoryLog?
    public var isBranch: Bool { mode == "BRANCH_GRAPH" }
    private enum CodingKeys: String, CodingKey {
        case routeMode, sessionId, status, version, currentNodeId, recommendedNodeId, nodeStates, lockReasons, thoughts, decisionLog
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decisionLog = try? c.decode(PlayBranchHistoryLog.self, forKey: .decisionLog)
        mode = try c.decodeIfPresent(String.self, forKey: .routeMode)
        sessionID = try c.playInt(.sessionId); status = try c.decodeIfPresent(String.self, forKey: .status)
        version = try c.playInt(.version); currentNodeID = try c.playInt(.currentNodeId)
        recommendedNodeID = try c.playInt(.recommendedNodeId)
        thoughts = try c.decodeIfPresent([PlayWireValue].self, forKey: .thoughts) ?? []
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
    public let eggs: [JourneyEgg]
    public let topicID: Int?
    public let topicName: String?
    public let topicDescription: String?
    public let mode: Int?
    public let playable: Bool?
    public let registered: Bool?
    /// Server-owned operational spectator fact; never implies registration or player rewards.
    public let leadSpectator: Bool?
    public let selfPlay: Bool?
    public let total: Int?
    public let doneCount: Int?
    public let timeNote: String?
    /// Kept verbatim. No server timezone contract: never infer expiry from local parsing.
    public let expiresAt: String?
    public let nodes: [PlayNode]
    public let chapters: [PlayChapter]
    public let routeState: PlayRouteState?
    /// FE-STORY mode 2 chapter counts. Nil unless both are present and consistent.
    public let storyUnlocked: Int?
    public let storyTotal: Int?
    /// CG-ALL-11 (hengyin #866): how this run was started. Nil = an ordinary start (or the
    /// server did not say); unknown values are nil, never guessed.
    public let runStartMode: PlayRunStartMode?
    /// CG-ALL-11 (hengyin #866): the route's public alternate start stations (city routes only).
    public let altStations: [PlayAltStation]
    /// FE-G7 (hengyin #866): true only when no delivered node carries a game. Nil = no verdict.
    public let perkOnly: Bool?
    private enum CodingKeys: String, CodingKey {
        case topicId, topicName, topicDesc, mode, playable, registered, leadSpectator, selfPlay, total, doneCount
        case timeNote, expiresAt, nodes, chapters, routeState, eggs, storyUnlocked, storyTotal
        case runStartMode, altStations, perkOnly
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eggs = JourneyEgg.project((try? c.decode(PlayWireValue.self, forKey: .eggs)) ?? .null)
        topicID = try c.playInt(.topicId); topicName = try c.decodeIfPresent(String.self, forKey: .topicName)
        topicDescription = try c.decodeIfPresent(String.self, forKey: .topicDesc)
        mode = try c.playInt(.mode); playable = try c.playBool(.playable)
        registered = try? c.decode(Bool.self, forKey: .registered); selfPlay = try c.playBool(.selfPlay)
        leadSpectator = try c.decodeIfPresent(Bool.self, forKey: .leadSpectator)
        total = try c.playInt(.total); doneCount = try c.playInt(.doneCount)
        timeNote = try c.decodeIfPresent(String.self, forKey: .timeNote)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt)
        // Required array: missing/null/non-object rows are errors, never an empty route.
        nodes = try c.decode([PlayNode].self, forKey: .nodes)
        chapters = try c.decodeIfPresent([PlayChapter].self, forKey: .chapters) ?? []
        routeState = try c.decodeIfPresent(PlayRouteState.self, forKey: .routeState)
        let unlocked = try? c.playInt(.storyUnlocked), storyCount = try? c.playInt(.storyTotal)
        if let unlocked, let storyCount, storyCount >= 0, (0...storyCount).contains(unlocked) {
            storyUnlocked = unlocked; storyTotal = storyCount
        } else { storyUnlocked = nil; storyTotal = nil }
        // Additive #866 fields: malformed means unknown and never fails the route read.
        runStartMode = PlayRunStartMode(raw: try? c.decodeIfPresent(String.self, forKey: .runStartMode))
        altStations = PlayAltStation.project((try? c.decode(PlayWireValue.self, forKey: .altStations)) ?? .null)
        perkOnly = try? c.decodeIfPresent(Bool.self, forKey: .perkOnly)
        guard Set(nodes.map(\.id)).count == nodes.count, Set(chapters.map(\.id)).count == chapters.count,
              total.map({ $0 >= 0 }) ?? true, doneCount.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
    }
    public var allDone: Bool { if let total, let doneCount { return total > 0 && doneCount >= total }; return false }
}

/// CG-ALL-11 (hengyin #866 `PlayRunStartModeService`): DESK = the run was started without
/// a location check (rewards capped to XP and badges); ALT = started at a public alternate
/// station. Only these two exact codes are recognized, matching the server's `normalize`.
public enum PlayRunStartMode: String, Equatable, CaseIterable {
    case desk = "DESK", alt = "ALT"
    public init?(raw: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), let mode = Self(rawValue: raw) else { return nil }
        self = mode
    }
    /// 桌面完成 / 替代站完成.
    public var labelKey: String { self == .desk ? "playx.completion.desk" : "playx.completion.alternate" }
}

/// One `altStations` row: `id`, `name`, `longitude`, `latitude` (#866 `selectAltStations`).
public struct PlayAltStation: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let longitude: Double?
    public let latitude: Double?
    public init(id: Int, name: String?, longitude: Double?, latitude: Double?) {
        self.id = id; self.name = name; self.longitude = longitude; self.latitude = latitude
    }
    /// Rows without a positive id, and duplicate ids, are dropped. At most 20 (server limit).
    static func project(_ value: PlayWireValue) -> [PlayAltStation] {
        var seen = Set<Int>(), result: [PlayAltStation] = []
        for row in value.array ?? [] {
            guard let id = row["id"].integer ?? row["id"].text.flatMap({ Int($0) }), id > 0, seen.insert(id).inserted else { continue }
            func coordinate(_ key: String) -> Double? {
                let raw = row[key].double ?? row[key].text.flatMap(Double.init)
                return raw.flatMap { $0.isFinite ? $0 : nil }
            }
            let name = row["name"].text?.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(.init(id: id, name: name?.isEmpty == false ? name : nil, longitude: coordinate("longitude"), latitude: coordinate("latitude")))
            if result.count == 20 { break }
        }
        return result
    }
}

/// The optional `/api/play/arrive` start-mode fields (#866 `ApiPlayProgressController`).
/// Absent = the original start path, unchanged. ALT must name one of this route's
/// `altStations`; DESK never carries a station.
public struct PlayRunStartRequest: Equatable {
    public let mode: PlayRunStartMode
    public let altStationID: Int?
    public init(mode: PlayRunStartMode, altStationID: Int? = nil, offered: [PlayAltStation] = []) throws {
        switch mode {
        case .desk: guard altStationID == nil else { throw APIError.invalidRequest }
        case .alt: guard let id = altStationID, id > 0, offered.contains(where: { $0.id == id }) else { throw APIError.invalidRequest }
        }
        self.mode = mode; self.altStationID = altStationID
    }
    public var fields: [String: String] {
        var value = ["startMode": mode.rawValue]
        if let altStationID { value["altStationId"] = String(altStationID) }
        return value
    }
}

/// FE-G5 (hengyin #866 `PlayNodeQueryApplication` + `PerkDisplayTerms`): a node's perk.
/// `included` / `extraSpendText` / `reserveRequired` are present only when the merchant
/// declared them; absent or malformed values stay nil and nothing is shown.
public struct PlayNodePerk: Decodable, Equatable {
    public let name: String?
    public let redeemRule: String?
    public let included: Bool?
    public let extraSpendText: String?
    public let reserveRequired: Bool?
    private enum CodingKeys: String, CodingKey { case name, redeemRule, included, extraSpendText, reserveRequired }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        redeemRule = try? c.decodeIfPresent(String.self, forKey: .redeemRule)
        included = try? c.decodeIfPresent(Bool.self, forKey: .included)
        let spend = (try? c.decodeIfPresent(String.self, forKey: .extraSpendText))?.trimmingCharacters(in: .whitespacesAndNewlines)
        extraSpendText = spend?.isEmpty == false ? spend : nil
        reserveRequired = try? c.decodeIfPresent(Bool.self, forKey: .reserveRequired)
    }
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
    func playCoordinate(_ key: Key) -> Double? {
        let value = (try? decode(Double.self, forKey: key)) ?? (try? decode(String.self, forKey: key)).flatMap(Double.init)
        return value.flatMap { $0.isFinite ? $0 : nil }
    }
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
